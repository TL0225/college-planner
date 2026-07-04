// CareerATSService.swift
// Feature: Career
// Purpose: HR-grade composite resume ↔ job scoring with platform profiles and NL semantics.

import Foundation
import CollegeCareer

struct CareerATSScoreBundle: Sendable {
    var rows: [CareerResumeMatchRow]
    var recommendedResumeID: UUID?
    var usedPartialFallback: Bool
}

struct CareerATSPostingSnapshot: Sendable {
    let postingID: UUID
    let companySlug: String
    let externalPath: String?
    let title: String
    let jobDescriptionText: String?
    let requirementsText: String?
    let descriptionHash: String?

    @MainActor
    init(posting: JobBoardPosting) {
        postingID = posting.id
        companySlug = posting.companySlug
        externalPath = posting.externalPath
        title = posting.title ?? ""
        jobDescriptionText = posting.jobDescriptionText
        requirementsText = posting.requirementsText
        descriptionHash = posting.descriptionHash
    }

    @MainActor
    init(application: JobApplication) {
        postingID = application.id
        companySlug = CareerRepository.CareerResumeJobMatchKey.companySlug(for: application)
        externalPath = CareerRepository.CareerResumeJobMatchKey.manualApplicationExternalPath(application.id)
        title = application.title ?? ""
        jobDescriptionText = application.jobDescriptionText
        requirementsText = nil
        if let jd = application.jobDescriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !jd.isEmpty {
            descriptionHash = CareerResumeHashing.hash(jobDescriptionPlain: jd)
        } else {
            descriptionHash = nil
        }
    }

    init(
        postingID: UUID,
        companySlug: String,
        externalPath: String?,
        title: String,
        jobDescriptionText: String?,
        requirementsText: String?,
        descriptionHash: String?
    ) {
        self.postingID = postingID
        self.companySlug = companySlug
        self.externalPath = externalPath
        self.title = title
        self.jobDescriptionText = jobDescriptionText
        self.requirementsText = requirementsText
        self.descriptionHash = descriptionHash
    }
}

actor CareerATSService {
    static let shared = CareerATSService()

    private static let resumeEmbedBudget = 6_000
    private static let jdEmbedBudget = 4_000

    func scoreAllResumes(
        posting: CareerATSPostingSnapshot,
        platform: JobBoardPlatform,
        priority: MLXTaskPriority = .userInitiated
    ) async -> CareerATSScoreBundle {
        await BackgroundServiceOnDemand.runReturning(id: "career_ats_lookup") {
            await CareerATSService.shared.scoreAllResumesImpl(
                posting: posting,
                platform: platform,
                priority: priority
            )
        }
    }

    func scoreAllResumesImpl(
        posting: CareerATSPostingSnapshot,
        platform: JobBoardPlatform,
        priority: MLXTaskPriority = .userInitiated
    ) async -> CareerATSScoreBundle {
        let scoringProfile = CareerATSScoringProfile.profile(for: platform)
        let work = await Self.prepareScoringWork(posting: posting)
        guard let work, !work.resumes.isEmpty, !work.jobDescription.isEmpty else {
            return CareerATSScoreBundle(rows: [], recommendedResumeID: nil, usedPartialFallback: false)
        }

        if let externalPath = posting.externalPath,
           let cachedBundle = await Self.tryCachedScoreBundle(
               work: work,
               posting: posting,
               externalPath: externalPath
           ) {
            return cachedBundle
        }

        var rows: [CareerResumeMatchRow] = []
        var usedPartialFallback = !CareerFoundationModelsJSONService.isAvailable()

        let keywords = Self.extractKeywords(from: work.jobDescription)
        let jdEmbedText = String(work.jobDescription.prefix(Self.jdEmbedBudget))
        let jdNLVector = await CareerNLSemanticEmbedding.embed(jdEmbedText)
        let jdLexicalVector: [Float]?
        if jdNLVector == nil {
            do {
                jdLexicalVector = try await CatalogEmbeddingRuntime.shared.embedLexical(
                    text: jdEmbedText,
                    priority: priority
                )
            } catch {
                jdLexicalVector = nil
                usedPartialFallback = true
            }
        } else {
            jdLexicalVector = nil
        }

        for resume in work.resumes {
            if Task.isCancelled { break }

            if let externalPath = posting.externalPath,
               let cachedRow = await Self.tryCachedMatchRow(
                   resume: resume,
                   work: work,
                   posting: posting,
                   externalPath: externalPath
               ) {
                rows.append(cachedRow)
                continue
            }

            let resumeText = work.resumeTexts[resume.id] ?? ""
            guard !resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let structuredProfile = work.structuredProfiles[resume.id]

            let keywordResult = Self.placementKeywordScore(
                structuredProfile: structuredProfile,
                resumeText: resumeText,
                keywords: keywords,
                mode: scoringProfile.keywordMatchMode,
                usePlacementMultipliers: scoringProfile.usePlacementMultipliers
            )

            var semanticScore = 0
            if let jdNLVector, !jdNLVector.isEmpty {
                if let resumeVector = await CareerNLSemanticEmbedding.embedExperienceWeighted(
                    profile: structuredProfile,
                    fullText: String(resumeText.prefix(Self.resumeEmbedBudget))
                ), !resumeVector.isEmpty {
                    semanticScore = Int((CareerNLSemanticEmbedding.cosineSimilarity(jdNLVector, resumeVector) * 100).rounded())
                } else {
                    usedPartialFallback = true
                }
            } else if let jdLexicalVector, !jdLexicalVector.isEmpty {
                let resumeEmbedText = String(resumeText.prefix(Self.resumeEmbedBudget))
                if let resumeVector = try? await CatalogEmbeddingRuntime.shared.embedLexical(
                    text: resumeEmbedText,
                    priority: priority
                ), !resumeVector.isEmpty {
                    semanticScore = Int((Self.cosineSimilarity(jdLexicalVector, resumeVector) * 100).rounded())
                } else {
                    usedPartialFallback = true
                }
            }

            let experienceAnalysis = CareerExperienceAnalyzer.analyze(
                jdText: work.jobDescription,
                structuredProfile: structuredProfile
            )
            let achievementAnalysis = CareerAchievementScorer.analyze(profile: structuredProfile)
            let skillsGap = CareerTransferableSkillsExpander.analyze(
                requiredSkills: keywords,
                profile: structuredProfile,
                resumeText: resumeText
            )

            let roleFit = CareerResumeRoleFitAnalyzer.analyze(
                jobTitle: work.jobTitle,
                jobDescription: work.jobDescription,
                profile: structuredProfile,
                targetRole: work.targetRoles[resume.id],
                detectedDomains: work.detectedDomains[resume.id] ?? []
            )

            if roleFit.alignmentScore < 50 {
                semanticScore = Int((Double(semanticScore) * Double(roleFit.alignmentScore) / 100.0).rounded())
            }

            let compareContext = CareerResumeCompareContext(
                scoringProfile: scoringProfile,
                experienceAnalysis: experienceAnalysis,
                skillsGap: skillsGap,
                achievementAnalysis: achievementAnalysis,
                structuredProfile: structuredProfile
            )

            let llmResult = await CareerAIService.shared.compareResume(
                resumeDocumentID: resume.id,
                jobDescriptionText: work.jobDescription,
                jobTitle: work.jobTitle,
                platform: platform,
                context: compareContext,
                using: await MainActor.run { CollegePersistence.shared }
            )

            let llmScore = llmResult?.overallScore
                ?? Int((Double(keywordResult.score) * 0.55 + Double(semanticScore) * 0.45).rounded())

            if llmResult == nil { usedPartialFallback = true }

            let weightSum = scoringProfile.keywordWeight
                + scoringProfile.semanticWeight
                + scoringProfile.experienceWeight
                + scoringProfile.achievementWeight
                + scoringProfile.llmWeight
                + scoringProfile.transferableWeight

            var overall = Int((
                Double(keywordResult.score) * scoringProfile.keywordWeight
                + Double(semanticScore) * scoringProfile.semanticWeight
                + Double(experienceAnalysis.score) * scoringProfile.experienceWeight
                + Double(achievementAnalysis.achievementScore) * scoringProfile.achievementWeight
                + Double(llmScore) * scoringProfile.llmWeight
                + Double(skillsGap.transferableScore) * scoringProfile.transferableWeight
            ) / weightSum)

            if scoringProfile.useRequiredSkillGating {
                let missingCount = skillsGap.entries.filter { $0.status == "missing" }.count
                if missingCount > keywords.count / 2, keywords.count >= 4 {
                    overall = min(overall, 55)
                }
            }

            overall = Int((Double(overall) * 0.82 + Double(roleFit.alignmentScore) * 0.18).rounded())
            if roleFit.alignmentScore < 35 {
                overall = min(overall, max(roleFit.alignmentScore + 10, 28))
            }

            let tip = CareerATSAdviceValidator.validatedTip(llmResult?.tip) ?? ""
            let row = CareerResumeMatchRow(
                resumeDocumentID: resume.id,
                displayName: resume.displayName,
                overallScore: min(100, max(0, overall)),
                keywordScore: keywordResult.score,
                semanticScore: semanticScore,
                experienceScore: experienceAnalysis.score,
                matchingSkills: llmResult?.matchingSkills ?? keywordResult.matching,
                missingKeywords: llmResult?.missingKeywords ?? keywordResult.missing,
                tip: tip,
                isRecommended: false,
                portalTips: llmResult?.portalTips,
                courseSkillGaps: llmResult?.courseSkillGaps,
                platformProfileName: scoringProfile.name,
                experienceGapNote: experienceAnalysis.gapNote,
                candidateYearsMonths: experienceAnalysis.candidateYearsMonthsLabel,
                requiredYearsMin: experienceAnalysis.requiredYearsMin,
                requiredYearsMax: experienceAnalysis.requiredYearsMax,
                transferableScore: skillsGap.transferableScore,
                achievementScore: achievementAnalysis.achievementScore,
                trajectoryNote: achievementAnalysis.trajectoryNote,
                seniorityAlignmentNote: achievementAnalysis.seniorityAlignmentNote,
                skillsGapTaxonomy: skillsGap.entries,
                roleFitScore: roleFit.alignmentScore,
                roleMismatchNote: roleFit.mismatchNote,
                resumeTargetRole: roleFit.resumeTargetRole
            )
            rows.append(row)
        }

        rows.sort { $0.overallScore > $1.overallScore }
        if let best = rows.first {
            rows[0] = Self.markRecommended(best)
        }

        let persistedRows = await MainActor.run {
            Self.persistMatches(rows: rows, posting: posting, descriptionHash: work.descriptionHash)
        }

        return CareerATSScoreBundle(
            rows: persistedRows,
            recommendedResumeID: persistedRows.first?.resumeDocumentID,
            usedPartialFallback: usedPartialFallback
        )
    }

    private static func markRecommended(_ row: CareerResumeMatchRow) -> CareerResumeMatchRow {
        CareerResumeMatchRow(
            id: row.id,
            resumeDocumentID: row.resumeDocumentID,
            displayName: row.displayName,
            overallScore: row.overallScore,
            keywordScore: row.keywordScore,
            semanticScore: row.semanticScore,
            experienceScore: row.experienceScore,
            matchingSkills: row.matchingSkills,
            missingKeywords: row.missingKeywords,
            tip: row.tip,
            isRecommended: true,
            scoreDelta: row.scoreDelta,
            portalTips: row.portalTips,
            courseSkillGaps: row.courseSkillGaps,
            platformProfileName: row.platformProfileName,
            experienceGapNote: row.experienceGapNote,
            candidateYearsMonths: row.candidateYearsMonths,
            requiredYearsMin: row.requiredYearsMin,
            requiredYearsMax: row.requiredYearsMax,
            transferableScore: row.transferableScore,
            achievementScore: row.achievementScore,
            trajectoryNote: row.trajectoryNote,
            seniorityAlignmentNote: row.seniorityAlignmentNote,
            skillsGapTaxonomy: row.skillsGapTaxonomy,
            roleFitScore: row.roleFitScore,
            roleMismatchNote: row.roleMismatchNote,
            resumeTargetRole: row.resumeTargetRole
        )
    }

    private struct ScoringWork: Sendable {
        let resumes: [ResumeRow]
        let resumeTexts: [UUID: String]
        let structuredProfiles: [UUID: CareerResumeStructuredProfile]
        let targetRoles: [UUID: String]
        let detectedDomains: [UUID: [String]]
        let jobDescription: String
        let jobTitle: String
        let descriptionHash: String?
    }

    private struct ResumeRow: Sendable {
        let id: UUID
        let displayName: String
        let parsedTextHash: String?
    }

    private static func prepareScoringWork(posting: CareerATSPostingSnapshot) async -> ScoringWork? {
        let prepared = await MainActor.run { () -> (ScoringSnapshot, VaultRepository)? in
            let persistence = CollegePersistence.shared
            let docs = VaultReadBridge.careerResumeDocuments(collegePersistence: persistence)
                .filter { !persistence.careerResumeMetadata(for: $0).archived }
            let jd = [
                posting.jobDescriptionText ?? "",
                posting.requirementsText ?? "",
            ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

            let resumeSnapshots = docs.map { doc -> ResumeSnapshot in
                let meta = persistence.careerResumeMetadata(for: doc)
                let domains: [String] = {
                    guard let json = meta.detectedDomainsJSON,
                          let data = json.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode([String].self, from: data)
                    else { return [] }
                    return decoded
                }()
                return ResumeSnapshot(
                    id: doc.id,
                    displayName: doc.customDisplayName ?? doc.fileName,
                    parsedTextHash: meta.parsedTextHash,
                    structuredProfile: meta.structuredProfile,
                    targetRole: meta.targetRole,
                    detectedDomains: domains,
                    relativePath: doc.localRelativePath,
                    fileName: doc.fileName
                )
            }
            return (
                ScoringSnapshot(
                    resumes: resumeSnapshots,
                    jobDescription: jd,
                    jobTitle: posting.title,
                    descriptionHash: posting.descriptionHash
                ),
                persistence.vaultRepository
            )
        }

        guard let snapshot = prepared?.0, let vaultRepository = prepared?.1 else { return nil }
        guard !snapshot.resumes.isEmpty, !snapshot.jobDescription.isEmpty else { return nil }

        var texts: [UUID: String] = [:]
        var profiles: [UUID: CareerResumeStructuredProfile] = [:]
        var targetRoles: [UUID: String] = [:]
        var detectedDomains: [UUID: [String]] = [:]
        var rows: [ResumeRow] = []
        for resume in snapshot.resumes {
            rows.append(ResumeRow(
                id: resume.id,
                displayName: resume.displayName,
                parsedTextHash: resume.parsedTextHash
            ))
            if let structured = resume.structuredProfile {
                profiles[resume.id] = structured
            }
            if let role = resume.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
                targetRoles[resume.id] = role
            }
            if !resume.detectedDomains.isEmpty {
                detectedDomains[resume.id] = resume.detectedDomains
            }

            if !resume.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tempURL = await vaultRepository.decryptedTempURLForStoredRelativePath(
                   resume.relativePath,
                   displayFileName: resume.fileName
               ) {
                let extracted = await CareerResumeTextExtractor.extract(from: tempURL)
                texts[resume.id] = extracted.plainText
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        return ScoringWork(
            resumes: rows,
            resumeTexts: texts,
            structuredProfiles: profiles,
            targetRoles: targetRoles,
            detectedDomains: detectedDomains,
            jobDescription: snapshot.jobDescription,
            jobTitle: snapshot.jobTitle,
            descriptionHash: snapshot.descriptionHash
        )
    }

    private struct ScoringSnapshot: Sendable {
        let resumes: [ResumeSnapshot]
        let jobDescription: String
        let jobTitle: String
        let descriptionHash: String?
    }

    private struct ResumeSnapshot: Sendable {
        let id: UUID
        let displayName: String
        let parsedTextHash: String?
        let structuredProfile: CareerResumeStructuredProfile?
        let targetRole: String?
        let detectedDomains: [String]
        let relativePath: String
        let fileName: String
    }

    private static func tryCachedScoreBundle(
        work: ScoringWork,
        posting: CareerATSPostingSnapshot,
        externalPath: String
    ) async -> CareerATSScoreBundle? {
        let rows = await MainActor.run {
            loadValidCachedMatchRows(work: work, posting: posting, externalPath: externalPath)
        }
        guard rows.count == work.resumes.count else { return nil }
        var sorted = rows.sorted { $0.overallScore > $1.overallScore }
        if let best = sorted.first {
            sorted[0] = markRecommended(best)
        }
        return CareerATSScoreBundle(
            rows: sorted,
            recommendedResumeID: sorted.first?.resumeDocumentID,
            usedPartialFallback: false
        )
    }

    private static func tryCachedMatchRow(
        resume: ResumeRow,
        work: ScoringWork,
        posting: CareerATSPostingSnapshot,
        externalPath: String
    ) async -> CareerResumeMatchRow? {
        await MainActor.run {
            cachedMatchRow(for: resume, work: work, posting: posting, externalPath: externalPath)
        }
    }

    @MainActor
    private static func loadValidCachedMatchRows(
        work: ScoringWork,
        posting: CareerATSPostingSnapshot,
        externalPath: String
    ) -> [CareerResumeMatchRow] {
        work.resumes.compactMap { resume in
            cachedMatchRow(for: resume, work: work, posting: posting, externalPath: externalPath)
        }
    }

    @MainActor
    private static func cachedMatchRow(
        for resume: ResumeRow,
        work: ScoringWork,
        posting: CareerATSPostingSnapshot,
        externalPath: String
    ) -> CareerResumeMatchRow? {
        guard let descriptionHash = work.descriptionHash,
              let resumeHash = resume.parsedTextHash,
              !descriptionHash.isEmpty,
              !resumeHash.isEmpty else { return nil }

        let repo = CollegePersistence.shared.careerRepository
        guard let match = try? repo.fetchResumeJobMatch(
            companySlug: posting.companySlug,
            externalPath: externalPath,
            resumeDocumentID: resume.id
        ),
        match.descriptionHashAtScore == descriptionHash,
        match.resumeHashAtScore == resumeHash else { return nil }

        return matchRow(from: match, displayName: resume.displayName)
    }

    @MainActor
    private static func matchRow(from match: CareerResumeJobMatch, displayName: String) -> CareerResumeMatchRow {
        let decoded: CareerResumeCompareResult? = {
            guard let json = match.resultJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data)
        }()
        let missingKeywords: [String] = {
            if let json = match.missingKeywordsJSON,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return decoded
            }
            return decoded?.missingKeywords ?? []
        }()

        return CareerResumeMatchRow(
            resumeDocumentID: match.resumeDocumentID,
            displayName: displayName,
            overallScore: match.overallScore,
            keywordScore: match.keywordScore,
            semanticScore: match.semanticScore,
            experienceScore: match.experienceScore,
            matchingSkills: decoded?.matchingSkills ?? [],
            missingKeywords: missingKeywords,
            tip: CareerATSAdviceValidator.validatedTip(decoded?.tip) ?? "",
            isRecommended: match.recommendedForPosting,
            portalTips: decoded?.portalTips,
            courseSkillGaps: decoded?.courseSkillGaps,
            experienceGapNote: decoded?.experienceGapExplanation,
            transferableScore: 0,
            achievementScore: 0,
            roleFitScore: 0
        )
    }

    @MainActor
    private static func persistMatches(
        rows: [CareerResumeMatchRow],
        posting: CareerATSPostingSnapshot,
        descriptionHash: String?
    ) -> [CareerResumeMatchRow] {
        guard let path = posting.externalPath else { return rows }
        let persistence = CollegePersistence.shared
        let repo = persistence.careerRepository
        var enriched: [CareerResumeMatchRow] = []

        for row in rows {
            let previousScore = try? repo.fetchResumeJobMatch(
                companySlug: posting.companySlug,
                externalPath: path,
                resumeDocumentID: row.resumeDocumentID
            ).map(\.overallScore)
            let resultJSON: String? = {
                let result = CareerResumeCompareResult(
                    matchingSkills: row.matchingSkills,
                    missingKeywords: row.missingKeywords,
                    tip: row.tip,
                    overallScore: row.overallScore,
                    keywordScore: row.keywordScore,
                    semanticScore: row.semanticScore,
                    experienceScore: row.experienceScore,
                    courseSkillGaps: row.courseSkillGaps,
                    portalTips: row.portalTips,
                    experienceGapExplanation: row.experienceGapNote,
                    transferableSkillsNoted: row.skillsGapTaxonomy?
                        .filter { $0.status == "transferable" }
                        .map(\.skill)
                )
                guard let data = try? JSONEncoder().encode(result),
                      let json = String(data: data, encoding: .utf8) else { return nil }
                return json
            }()

            let resumeHash: String? = {
                guard let doc = try? persistence.vaultRepository.fetchDocument(id: row.resumeDocumentID) else { return nil }
                return repo.careerResumeMetadata(for: doc).parsedTextHash
            }()

            let match = try? repo.upsertResumeJobMatch(
                companySlug: posting.companySlug,
                externalPath: path,
                resumeDocumentID: row.resumeDocumentID,
                overallScore: row.overallScore,
                keywordScore: row.keywordScore,
                semanticScore: row.semanticScore,
                experienceScore: row.experienceScore,
                missingKeywords: row.missingKeywords,
                recommendedForPosting: row.isRecommended,
                resultJSON: resultJSON,
                descriptionHash: descriptionHash,
                resumeHash: resumeHash
            )

            if let match {
                try? repo.appendResumeJobMatchSnapshot(matchID: match.id, overallScore: row.overallScore)
            }

            let delta = previousScore.map { row.overallScore - $0 }
            enriched.append(CareerResumeMatchRow(
                id: row.id,
                resumeDocumentID: row.resumeDocumentID,
                displayName: row.displayName,
                overallScore: row.overallScore,
                keywordScore: row.keywordScore,
                semanticScore: row.semanticScore,
                experienceScore: row.experienceScore,
                matchingSkills: row.matchingSkills,
                missingKeywords: row.missingKeywords,
                tip: row.tip,
                isRecommended: row.isRecommended,
                scoreDelta: delta,
                portalTips: row.portalTips,
                courseSkillGaps: row.courseSkillGaps,
                platformProfileName: row.platformProfileName,
                experienceGapNote: row.experienceGapNote,
                candidateYearsMonths: row.candidateYearsMonths,
                requiredYearsMin: row.requiredYearsMin,
                requiredYearsMax: row.requiredYearsMax,
                transferableScore: row.transferableScore,
                achievementScore: row.achievementScore,
                trajectoryNote: row.trajectoryNote,
                seniorityAlignmentNote: row.seniorityAlignmentNote,
                skillsGapTaxonomy: row.skillsGapTaxonomy,
                roleFitScore: row.roleFitScore,
                roleMismatchNote: row.roleMismatchNote,
                resumeTargetRole: row.resumeTargetRole
            ))
        }
        return enriched
    }

    private static func extractKeywords(from text: String) -> [String] {
        let focus = requirementFocusedText(from: text)
        let stop: Set<String> = [
            "that", "this", "with", "from", "your", "have", "will", "been", "were", "their", "what", "when", "which",
            "about", "into", "more", "than", "then", "some", "such", "other", "also", "only", "very", "just", "like",
            "work", "team", "using", "skills", "experience", "years", "able", "role", "must", "required",
            "please", "every", "person", "human", "disease", "request", "protected", "reasonable", "disability",
            "accommodation", "employment", "equal", "opportunity", "programs", "preferred", "city", "state",
            "company", "business", "including", "within", "across", "among", "through", "under", "over"
        ]
        var counts: [String: Int] = [:]
        for token in focus.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "/" }).map(String.init) {
            let lower = token.lowercased()
            guard lower.count > 3, !stop.contains(lower) else { continue }
            counts[lower, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(20).map(\.key)
    }

    private static func requirementFocusedText(from text: String) -> String {
        let lower = text.lowercased()
        let markers = [
            "who you are", "what you'll do", "what you will do", "requirements", "qualifications",
            "minimum", "preferred", "about the role", "you have", "you are"
        ]
        var chunks: [String] = []
        for marker in markers {
            if let range = lower.range(of: marker) {
                let start = range.lowerBound
                let end = lower.index(start, offsetBy: 2_500, limitedBy: lower.endIndex) ?? lower.endIndex
                chunks.append(String(text[start..<end]))
            }
        }
        return chunks.isEmpty ? text : chunks.joined(separator: "\n")
    }

    private static func placementKeywordScore(
        structuredProfile: CareerResumeStructuredProfile?,
        resumeText: String,
        keywords: [String],
        mode: CareerATSScoringProfile.KeywordMatchMode,
        usePlacementMultipliers: Bool
    ) -> (score: Int, matching: [String], missing: [String]) {
        guard !keywords.isEmpty else { return (0, [], []) }

        let zones = keywordZones(profile: structuredProfile, resumeText: resumeText)
        var matching: [String] = []
        var missing: [String] = []
        var weightedHits: Double = 0
        let maxPerKeyword = usePlacementMultipliers ? 2.5 : 1.0

        for kw in keywords {
            let needle = normalizeKeyword(kw, mode: mode)
            let multiplier = bestMultiplier(for: needle, zones: zones, resumeText: resumeText, mode: mode)
            if multiplier > 0 {
                matching.append(kw)
                weightedHits += usePlacementMultipliers ? multiplier : 1.0
            } else {
                missing.append(kw)
            }
        }

        let score: Int
        if usePlacementMultipliers {
            let denominator = Double(keywords.count) * maxPerKeyword
            score = denominator > 0 ? Int((weightedHits / denominator * 100).rounded()) : 0
        } else {
            score = Int((Double(matching.count) / Double(keywords.count) * 100).rounded())
        }
        return (score, matching, missing)
    }

    private struct KeywordZones: Sendable {
        var summary: String
        var skills: String
        var recentBullets: String
        var oldBullets: String
        var fullLower: String
    }

    private static func keywordZones(
        profile: CareerResumeStructuredProfile?,
        resumeText: String
    ) -> KeywordZones {
        let summary = profile?.summary?.lowercased() ?? ""
        let skills = profile?.skills.joined(separator: " ").lowercased()
        var recentBullets = ""
        var oldBullets = ""
        let now = Date()

        if let profile {
            for entry in profile.experience {
                let heading = entry.headingLines.joined(separator: " ")
                let yearsAgo = yearsSinceEnd(heading: heading, now: now)
                let block = (entry.headingLines + entry.bullets).joined(separator: "\n").lowercased()
                if let yearsAgo, yearsAgo <= 3 {
                    recentBullets += block + "\n"
                } else {
                    oldBullets += block + "\n"
                }
            }
        }

        return KeywordZones(
            summary: summary,
            skills: skills ?? "",
            recentBullets: recentBullets,
            oldBullets: oldBullets,
            fullLower: resumeText.lowercased()
        )
    }

    private static func bestMultiplier(
        for needle: String,
        zones: KeywordZones,
        resumeText: String,
        mode: CareerATSScoringProfile.KeywordMatchMode
    ) -> Double {
        func contains(_ haystack: String) -> Bool {
            keywordMatch(haystack: haystack, needle: needle, mode: mode)
        }

        if contains(zones.summary) { return 2.5 }
        if contains(zones.recentBullets) { return 1.5 }
        if contains(zones.oldBullets) { return 0.7 }
        if contains(zones.skills) { return 0.5 }
        if contains(zones.fullLower) { return 1.0 }
        return 0
    }

    private static func keywordMatch(
        haystack: String,
        needle: String,
        mode: CareerATSScoringProfile.KeywordMatchMode
    ) -> Bool {
        switch mode {
        case .exact:
            return haystack.range(of: "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b", options: .regularExpression) != nil
                || haystack.contains(needle)
        case .stemmed, .contextual:
            let stemmedHay = haystack.split(whereSeparator: { !$0.isLetter }).map { stem(String($0)) }
            return stemmedHay.contains(stem(needle)) || haystack.contains(needle)
        case .semantic:
            return haystack.contains(needle) || stemmedOverlap(haystack: haystack, needle: needle)
        }
    }

    private static func stemmedOverlap(haystack: String, needle: String) -> Bool {
        let needleStem = stem(needle)
        return haystack.split(whereSeparator: { !$0.isLetter })
            .map { stem(String($0)) }
            .contains(where: { $0.hasPrefix(needleStem) || needleStem.hasPrefix($0) })
    }

    private static func stem(_ word: String) -> String {
        var w = word.lowercased()
        for suffix in ["ing", "ed", "es", "s", "tion", "ment"] {
            if w.count > suffix.count + 2, w.hasSuffix(suffix) {
                w = String(w.dropLast(suffix.count))
                break
            }
        }
        return w
    }

    private static func normalizeKeyword(_ keyword: String, mode: CareerATSScoringProfile.KeywordMatchMode) -> String {
        switch mode {
        case .exact: return keyword.lowercased()
        default: return stem(keyword.lowercased())
        }
    }

    private static func yearsSinceEnd(heading: String, now: Date) -> Int? {
        let lower = heading.lowercased()
        if lower.contains("present") || lower.contains("current") { return 0 }
        if let year = heading.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).last,
           year > 1950 {
            let currentYear = Calendar.current.component(.year, from: now)
            return max(0, currentYear - year)
        }
        return nil
    }

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-6 else { return 0 }
        return Double(dot / denom)
    }
}

struct CareerResumeCompareContext: Sendable {
    var scoringProfile: CareerATSScoringProfile
    var experienceAnalysis: ExperienceAnalysis
    var skillsGap: SkillsGapTaxonomy
    var achievementAnalysis: AchievementAnalysis
    var structuredProfile: CareerResumeStructuredProfile?
}
