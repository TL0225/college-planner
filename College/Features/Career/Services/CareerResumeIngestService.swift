// CareerResumeIngestService.swift
// Feature: Career
// Purpose: Async resume ingest: extract text, hash, parser compliance, metadata write, assistant indexing.

import Foundation

actor CareerResumeIngestService {
    static let shared = CareerResumeIngestService()

    private var inFlight: Set<UUID> = []

    func ingest(documentID: UUID) async {
        await BackgroundServiceOnDemand.run(id: "career_resume_ingest") {
            await CareerResumeIngestService.shared.performIngest(documentID: documentID)
        }
    }

    private func performIngest(documentID: UUID) async {
        guard inFlight.insert(documentID).inserted else { return }
        defer {
            inFlight.remove(documentID)
            Task { @MainActor in
                CareerResumeIngestProgressStore.shared.clearProgress(for: documentID)
            }
        }

        await MainActor.run {
            Self.markIngestStarted(documentID: documentID)
            CareerResumeIngestProgressStore.shared.setProgress(.extracting, for: documentID)
        }

        let work = await MainActor.run { Self.prepareIngestWork(documentID: documentID) }
        guard let work else {
            await MainActor.run {
                Self.applyIngestFailure(documentID: documentID, message: "Could not read resume file.")
                BackgroundActivityReporter.finish(
                    id: BackgroundActivityCenter.resumeActivityID(documentID: documentID),
                    succeeded: false,
                    summary: String(localized: "resume.background.failed", defaultValue: "Could not read resume file.")
                )
            }
            return
        }

        let extraction = await CareerResumeTextExtractor.extract(from: work)
        defer { try? FileManager.default.removeItem(at: work) }

        let normalized = CareerResumeHashing.normalize(extraction.plainText)
        let textHash = CareerResumeHashing.hash(normalizedPlainText: normalized)
        let compliance = CareerResumeParserCompliance.analyze(
            plainText: extraction.plainText,
            pageCount: extraction.pageCount,
            usedOCR: extraction.usedOCR
        )

        let issuesJSON: String? = {
            guard let data = try? JSONEncoder().encode(compliance.issues),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        let normalizedText = CareerResumePlainTextNormalizer.normalize(extraction.plainText)

        let existingMeta = await MainActor.run {
            Self.metadata(for: documentID)
        }

        let structuredProfile: CareerResumeStructuredProfile
        if let canonical = existingMeta?.canonicalProfile {
            structuredProfile = canonical
        } else {
            await MainActor.run {
                CareerResumeIngestProgressStore.shared.setProgress(.structuring, for: documentID)
            }

            structuredProfile = await withCareerResumeIngestTimeout(
                seconds: CareerResumeIngestTimeouts.structuredParseSeconds
            ) {
                await CareerResumeStructuredParsePipeline.parse(plainText: normalizedText)
            } ?? CareerResumeStructuredParser.parse(plainText: normalizedText)
        }

        let structuredJSON: String? = {
            guard structuredProfile.hasContent,
                  let data = try? JSONEncoder().encode(structuredProfile),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        let enrichment = await BackgroundServiceOnDemand.runReturning(id: "career_resume_enrichment") {
            let domains = await CareerResumeIngestEnrichment.detectDomains(plainText: extraction.plainText)
            let staleSkills = CareerResumeIngestEnrichment.detectStaleSkills(plainText: extraction.plainText)
            let suggestedRole = await CareerResumeIngestEnrichment.suggestedTargetRole(plainText: extraction.plainText)
            return (domains, staleSkills, suggestedRole)
        }
        let domains = enrichment.0
        let domainsJSON: String? = {
            guard !domains.isEmpty,
                  let data = try? JSONEncoder().encode(domains),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        let staleSkills = enrichment.1
        let staleSkillsJSON: String? = {
            guard !staleSkills.isEmpty,
                  let data = try? JSONEncoder().encode(staleSkills),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        let suggestedRole = enrichment.2

        await MainActor.run {
            CareerResumeIngestProgressStore.shared.setProgress(.saving, for: documentID)
            Self.applyIngestResult(
                documentID: documentID,
                textHash: textHash,
                compliance: compliance,
                issuesJSON: issuesJSON,
                structuredJSON: structuredJSON,
                detectedDomainsJSON: domainsJSON,
                staleSkillsJSON: staleSkillsJSON,
                suggestedTargetRole: suggestedRole
            )
            BackgroundActivityReporter.finish(
                id: BackgroundActivityCenter.resumeActivityID(documentID: documentID),
                succeeded: structuredJSON != nil,
                summary: structuredJSON != nil
                    ? String(localized: "resume.background.finished", defaultValue: "Resume parsed")
                    : String(localized: "resume.background.partial", defaultValue: "Parser finished with limited fields")
            )
        }

        await VaultDocumentTextIndexer.shared.schedule(documentID: documentID)
    }

    @MainActor
    private static func prepareIngestWork(documentID: UUID) -> URL? {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID),
              !doc.isFolder,
              let readURL = persistence.decryptedTempURLForStoredRelativePath(
                  doc.localRelativePath,
                  displayFileName: doc.fileName
              ) else { return nil }
        return readURL
    }

    @MainActor
    private static func markIngestStarted(documentID: UUID) {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID) else { return }
        var meta = persistence.careerResumeMetadata(for: doc)
        meta.ingestCompletedAt = nil
        meta.ingestFailedAt = nil
        meta.parsedTextHash = nil
        meta.parserIssuesJSON = nil
        meta.parserHealthPercent = nil
        meta.structuredSectionsJSON = nil
        meta.detectedDomainsJSON = nil
        meta.staleSkillsJSON = nil
        // Preserve builder sidecar: buildMetadataJSON, documentJSON, canonicalProfileJSON, platformTarget
        try? persistence.careerRepository.setCareerResumeMetadata(meta, for: doc)
        persistence.bumpCareerRevision()
    }

    @MainActor
    private static func metadata(for documentID: UUID) -> CareerResumeMetadataV1? {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID) else { return nil }
        return persistence.careerResumeMetadata(for: doc)
    }

    @MainActor
    private static func applyIngestResult(
        documentID: UUID,
        textHash: String,
        compliance: CareerResumeParserCompliance.Report,
        issuesJSON: String?,
        structuredJSON: String?,
        detectedDomainsJSON: String?,
        staleSkillsJSON: String?,
        suggestedTargetRole: String?
    ) {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID) else { return }

        var meta = persistence.careerResumeMetadata(for: doc)
        let previousHash = meta.parsedTextHash
        meta.parsedTextHash = textHash
        meta.parserHealthPercent = compliance.healthPercent
        meta.parserScoredAt = .now
        meta.parserComplianceRaw = compliance.status.rawValue
        meta.parserIssuesJSON = issuesJSON
        meta.structuredSectionsJSON = structuredJSON
        meta.detectedDomainsJSON = detectedDomainsJSON
        meta.staleSkillsJSON = staleSkillsJSON
        meta.ingestFailedAt = nil
        if meta.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let suggestedTargetRole {
            meta.targetRole = suggestedTargetRole
        }
        meta.ingestCompletedAt = .now

        try? persistence.careerRepository.setCareerResumeMetadata(meta, for: doc)
        persistence.bumpVaultRevision()
        persistence.bumpCareerRevision()

        if previousHash != textHash {
            try? persistence.careerRepository.invalidateResumeJobMatches(resumeDocumentID: documentID)
        }

        if structuredJSON != nil {
            NotificationCenter.default.post(
                name: .careerResumeReadyForProfileImport,
                object: documentID
            )
        }
    }

    @MainActor
    private static func applyIngestFailure(documentID: UUID, message: String) {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID) else { return }

        let issue = ParserComplianceIssue(
            code: "ingest_failed",
            message: message,
            severity: .warning
        )
        let issuesJSON: String? = {
            guard let data = try? JSONEncoder().encode([issue]),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        var meta = persistence.careerResumeMetadata(for: doc)
        meta.parserComplianceRaw = ParserComplianceStatus.warning.rawValue
        meta.parserHealthPercent = 40
        meta.parserIssuesJSON = issuesJSON
        meta.ingestCompletedAt = nil
        meta.ingestFailedAt = .now

        try? persistence.careerRepository.setCareerResumeMetadata(meta, for: doc)
        persistence.bumpVaultRevision()
        persistence.bumpCareerRevision()
    }
}
