// JobBoardMatchEligibility.swift
// Feature: Career / Job Board
// Purpose: Central rules for when resume-match UI may appear on list and detail.

import Foundation
import CollegeCareer

/// Parsed resume context eligible for job comparison.
struct JobBoardResumeMatchContext: Equatable, Sendable {
    let documentID: UUID
    let profile: CareerResumeStructuredProfile
    let parsedTextHash: String?
}

/// List-row match presentation (no title-only fit labels).
enum JobBoardMatchListDisplay: Equatable, Sendable {
    case hidden
    case awaitingResumeParse
    case awaitingDescription
    case scored(overall: Int)
}

/// Detail-pane match presentation.
enum JobBoardDetailMatchState: Equatable, Sendable {
    case noResume
    case awaitingResumeParse
    case awaitingDescription
    case scoring
    case scored
}

enum JobBoardDetailInspectorTab: String, CaseIterable, Sendable {
    case match
    case job

    var title: String {
        switch self {
        case .match: return "Match"
        case .job: return "Job"
        }
    }
}

enum JobBoardMatchEligibility {
    // MARK: - Resume

    /// Structured profile usable for job match without waiting on PDF ingest when canonical sidecar exists.
    static func matchEligibleStructuredProfile(from metadata: CareerResumeMetadataV1) -> CareerResumeStructuredProfile? {
        if let canonical = metadata.canonicalProfile {
            return canonical
        }
        guard metadata.ingestCompletedAt != nil,
              let structured = metadata.structuredProfile
        else { return nil }
        return structured
    }

    /// Resume content hash for match-cache validation (canonical sidecar or ingest hash).
    static func effectiveParsedTextHash(for metadata: CareerResumeMetadataV1) -> String? {
        if let hash = metadata.parsedTextHash?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hash.isEmpty {
            return hash
        }
        guard let profile = metadata.canonicalProfile,
              let data = try? JSONEncoder().encode(profile),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return CareerResumeHashing.hash(normalizedPlainText: json)
    }

    static func resumeContext(from metadata: CareerResumeMetadataV1, documentID: UUID) -> JobBoardResumeMatchContext? {
        guard let profile = matchEligibleStructuredProfile(from: metadata) else { return nil }
        return JobBoardResumeMatchContext(
            documentID: documentID,
            profile: profile,
            parsedTextHash: effectiveParsedTextHash(for: metadata)
        )
    }

    static func hasPendingResumeParse(in metadata: CareerResumeMetadataV1) -> Bool {
        guard !metadata.archived else { return false }
        if matchEligibleStructuredProfile(from: metadata) != nil { return false }
        return metadata.ingestCompletedAt == nil
    }

    /// Prefer most recently ingested parse-complete resume; else first pending parse.
    static func pickPrimaryResume(
        documents: [(documentID: UUID, metadata: CareerResumeMetadataV1)]
    ) -> (documentID: UUID, metadata: CareerResumeMetadataV1)? {
        let nonArchived = documents.filter { !$0.metadata.archived }
        if let parsed = nonArchived
            .compactMap({ item -> (UUID, CareerResumeMetadataV1, Date)? in
                guard resumeContext(from: item.metadata, documentID: item.documentID) != nil else { return nil }
                let sortDate = item.metadata.ingestCompletedAt
                    ?? item.metadata.buildMetadata?.generatedDate
                    ?? .distantPast
                return (item.documentID, item.metadata, sortDate)
            })
            .max(by: { $0.2 < $1.2 })
        {
            return (parsed.0, parsed.1)
        }
        return nonArchived.first(where: { hasPendingResumeParse(in: $0.metadata) })
    }

    // MARK: - Job description

    static func hasUsableJobDescription(
        jobDescriptionText: String?,
        requirementsText: String?,
        detailScrapedAt: Date?
    ) -> Bool {
        guard detailScrapedAt != nil else { return false }
        let jd = (jobDescriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let req = (requirementsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !jd.isEmpty || !req.isEmpty
    }

    static func hasUsableJobDescription(_ posting: JobBoardPosting) -> Bool {
        hasUsableJobDescription(
            jobDescriptionText: posting.jobDescriptionText,
            requirementsText: posting.requirementsText,
            detailScrapedAt: posting.detailScrapedAt
        )
    }

    static func postingContentHash(
        jobDescriptionText: String?,
        requirementsText: String?
    ) -> String? {
        let jd = (jobDescriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let req = (requirementsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jd.isEmpty || !req.isEmpty else { return nil }
        return CareerResumeHashing.hashJobPostingContent(
            descriptionPlain: jd.isEmpty ? nil : jd,
            requirementsPlain: req.isEmpty ? nil : req
        )
    }

    // MARK: - Cache

    static func isMatchCacheValid(
        match: CareerResumeJobMatch,
        postingDescriptionHash: String?,
        resumeParsedTextHash: String?
    ) -> Bool {
        guard let postingDescriptionHash, !postingDescriptionHash.isEmpty else { return false }
        guard match.descriptionHashAtScore == postingDescriptionHash else { return false }
        guard let resumeParsedTextHash, !resumeParsedTextHash.isEmpty,
              let cachedResumeHash = match.resumeHashAtScore, !cachedResumeHash.isEmpty
        else { return false }
        return cachedResumeHash == resumeParsedTextHash
    }

    static func recommendedOverallScoreIfValid(
        match: CareerResumeJobMatch?,
        postingDescriptionHash: String?,
        resumeParsedTextHash: String?
    ) -> Int? {
        guard let match, match.recommendedForPosting,
              isMatchCacheValid(
                  match: match,
                  postingDescriptionHash: postingDescriptionHash,
                  resumeParsedTextHash: resumeParsedTextHash
              )
        else { return nil }
        return match.overallScore
    }

    // MARK: - List / detail display

    static func listDisplay(
        hasParsedResume: Bool,
        hasPendingParse: Bool,
        hasUsableJD: Bool,
        cachedOverallScore: Int?
    ) -> JobBoardMatchListDisplay {
        if hasParsedResume {
            if !hasUsableJD { return .awaitingDescription }
            if let cachedOverallScore { return .scored(overall: cachedOverallScore) }
            return .awaitingDescription
        }
        if hasPendingParse { return .awaitingResumeParse }
        return .hidden
    }

    static func detailMatchState(
        hasParsedResume: Bool,
        hasPendingParse: Bool,
        hasUsableJD: Bool,
        isScoring: Bool,
        hasScoredRows: Bool
    ) -> JobBoardDetailMatchState {
        if !hasParsedResume && !hasPendingParse { return .noResume }
        if hasPendingParse && !hasParsedResume { return .awaitingResumeParse }
        if !hasUsableJD { return .awaitingDescription }
        if isScoring { return .scoring }
        if hasScoredRows { return .scored }
        return .awaitingDescription
    }

    /// Resume to attach when promoting a posting from a list row (B19).
    @MainActor
    static func recommendedResumeID(
        for posting: JobBoardPosting,
        collegePersistence: CollegePersistence,
        resumeParsedTextHash: String?,
        fallbackDocumentID: UUID?
    ) -> UUID? {
        let path = posting.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return fallbackDocumentID }
        if let match = try? collegePersistence.careerRepository.recommendedMatchIfValid(
            companySlug: posting.companySlug,
            externalPath: path,
            postingDescriptionHash: posting.descriptionHash,
            resumeParsedTextHash: resumeParsedTextHash
        ) {
            return match.resumeDocumentID
        }
        return fallbackDocumentID
    }

    /// Fast path for job-detail navigation — one SwiftData fetch, no ATS re-score.
    @MainActor
    static func cachedMatchRows(
        for posting: JobBoardPosting,
        collegePersistence: CollegePersistence
    ) -> [CareerResumeMatchRow] {
        guard let externalPath = posting.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !externalPath.isEmpty
        else { return [] }

        let repo = collegePersistence.careerRepository
        let matches = (try? repo.fetchResumeJobMatches(
            companySlug: posting.companySlug,
            externalPath: externalPath
        )) ?? []
        guard !matches.isEmpty else { return [] }

        var rows: [CareerResumeMatchRow] = []
        for match in matches {
            let resumeMeta: CareerResumeMetadataV1 = {
                guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: match.resumeDocumentID)
                else { return .default }
                return collegePersistence.careerResumeMetadata(for: doc)
            }()
            guard isMatchCacheValid(
                match: match,
                postingDescriptionHash: posting.descriptionHash,
                resumeParsedTextHash: effectiveParsedTextHash(for: resumeMeta)
            ) else { continue }
            let displayName: String = {
                guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: match.resumeDocumentID)
                else { return "Resume" }
                return doc.customDisplayName ?? doc.fileName
            }()
            rows.append(careerResumeMatchRow(from: match, displayName: displayName))
        }
        rows.sort { $0.overallScore > $1.overallScore }
        if var best = rows.first {
            best = CareerResumeMatchRow(
                id: best.id,
                resumeDocumentID: best.resumeDocumentID,
                displayName: best.displayName,
                overallScore: best.overallScore,
                keywordScore: best.keywordScore,
                semanticScore: best.semanticScore,
                experienceScore: best.experienceScore,
                matchingSkills: best.matchingSkills,
                missingKeywords: best.missingKeywords,
                tip: best.tip,
                isRecommended: true,
                scoreDelta: best.scoreDelta,
                portalTips: best.portalTips,
                courseSkillGaps: best.courseSkillGaps,
                platformProfileName: best.platformProfileName,
                experienceGapNote: best.experienceGapNote,
                candidateYearsMonths: best.candidateYearsMonths,
                requiredYearsMin: best.requiredYearsMin,
                requiredYearsMax: best.requiredYearsMax,
                transferableScore: best.transferableScore,
                achievementScore: best.achievementScore,
                trajectoryNote: best.trajectoryNote,
                seniorityAlignmentNote: best.seniorityAlignmentNote,
                skillsGapTaxonomy: best.skillsGapTaxonomy,
                roleFitScore: best.roleFitScore,
                roleMismatchNote: best.roleMismatchNote,
                resumeTargetRole: best.resumeTargetRole
            )
            rows[0] = best
        }
        return rows
    }

    private static func careerResumeMatchRow(
        from match: CareerResumeJobMatch,
        displayName: String
    ) -> CareerResumeMatchRow {
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
}
