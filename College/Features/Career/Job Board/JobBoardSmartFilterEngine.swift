// JobBoardSmartFilterEngine.swift
// Feature: Career / Job Board
// Purpose: AI-assisted filtering and semantic ranking for unified smart boards.

import Foundation
import CollegeCareer

struct JobBoardFilteredPosting: Identifiable {
    let posting: JobBoardPosting
    let relevanceScore: Double
    let matchScore: Int?

    var id: UUID { posting.id }
}

struct JobBoardPostingEmbeddingSnapshot: Sendable {
    let id: UUID
    let summaryText: String
}

enum JobBoardSmartFilterEngine {
  // MARK: - AI interpretation

    @MainActor
    static func interpretQuery(_ query: String) async -> JobBoardSmartFilterInterpretation {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return JobBoardSmartFilterInterpretation() }

        if let ai = await interpretWithFoundationModels(trimmed) {
            return ai
        }
        return heuristicInterpret(trimmed)
    }

    @MainActor
    private static func interpretWithFoundationModels(_ query: String) async -> JobBoardSmartFilterInterpretation? {
        let prompt = """
        You help refine job board search filters. Given a student's natural-language job search, return JSON:
        {
          "keywords": ["role or domain terms"],
          "requiredSkills": ["specific skills or tools"],
          "jobTypes": ["internship", "full-time", "part-time", "contract"],
          "scheduleTypes": ["remote", "hybrid", "on-site"],
          "locations": ["city, state, or region phrases"],
          "minMatchScore": null or integer 0-100,
          "remoteOnly": null or boolean,
          "explanation": "one short sentence summarizing the interpreted search"
        }
        Use empty arrays when unsure. Only set minMatchScore when the user mentions match percentage or quality bar.
        Query: \(query)
        """
        guard let json = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JobBoardSmartFilterInterpretation.self, from: data)
        else { return nil }
        return decoded
    }

    static func heuristicInterpret(_ query: String) -> JobBoardSmartFilterInterpretation {
        let lower = query.lowercased()
        var interpretation = JobBoardSmartFilterInterpretation()
        interpretation.explanation = "Interpreted using keyword rules."

        let tokens = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "+" })
            .map(String.init)
            .filter { $0.count > 2 }

        let stopwords: Set<String> = [
            "and", "the", "for", "with", "that", "this", "from", "into", "jobs", "job", "role", "roles",
            "looking", "want", "need", "find", "show", "only", "prefer", "like", "work", "working",
        ]
        interpretation.keywords = tokens.filter { !stopwords.contains($0) }

        let jobTypeMap: [(String, String)] = [
            ("intern", "internship"), ("internship", "internship"),
            ("full-time", "full-time"), ("full time", "full-time"),
            ("part-time", "part-time"), ("part time", "part-time"),
            ("contract", "contract"), ("co-op", "co-op"), ("coop", "co-op"),
        ]
        for (needle, label) in jobTypeMap where lower.contains(needle) {
            interpretation.jobTypes.append(label)
        }

        let scheduleMap: [(String, String)] = [
            ("remote", "remote"), ("hybrid", "hybrid"), ("on-site", "on-site"),
            ("onsite", "on-site"), ("in office", "on-site"), ("in-office", "on-site"),
        ]
        for (needle, label) in scheduleMap where lower.contains(needle) {
            interpretation.scheduleTypes.append(label)
        }
        if lower.contains("remote only") || lower.contains("fully remote") {
            interpretation.remoteOnly = true
        }

        if let score = extractMinMatchScore(from: lower) {
            interpretation.minMatchScore = score
        }

        let skillHints = ["python", "swift", "java", "react", "aws", "kubernetes", "sql", "cybersecurity",
                          "machine learning", "data science", "ios", "android", "typescript", "rust", "go"]
        for skill in skillHints where lower.contains(skill) {
            interpretation.requiredSkills.append(skill)
        }

        interpretation.keywords = Array(Set(interpretation.keywords))
        interpretation.requiredSkills = Array(Set(interpretation.requiredSkills))
        interpretation.jobTypes = Array(Set(interpretation.jobTypes))
        interpretation.scheduleTypes = Array(Set(interpretation.scheduleTypes))
        return interpretation
    }

    private static func extractMinMatchScore(from lower: String) -> Int? {
        let patterns = [
            #"(\d{1,3})\s*%?\s*match"#,
            #"at least\s*(\d{1,3})"#,
            #"(\d{1,3})\s*%\s*or\s*higher"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: lower),
                  let value = Int(lower[range])
            else { continue }
            return min(100, max(0, value))
        }
        return nil
    }

  // MARK: - Filtering + ranking

    static func filterAndRank(
        postings: [JobBoardPosting],
        companies: [JobBoardCompany],
        criteria: JobBoardSmartFilterCriteria,
        sortOrder: JobBoardUnifiedSort,
        searchText: String,
        matchScoresByPath: [String: Int],
        queryEmbedding: [Float]?,
        postingEmbeddings: [UUID: [Float]]
    ) -> [JobBoardFilteredPosting] {
        let companySlugs = Set(companies.map(\.normalizedSlug))
        let inlineSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let smartTokens = tokenSet(from: criteria.keywords + criteria.requiredSkills + [criteria.smartQuery])
        let jobTypeTokens = tokenSet(from: criteria.jobTypeKeywords)
        let scheduleTokens = tokenSet(from: criteria.scheduleKeywords)
        let locationTokens = tokenSet(from: criteria.locationKeywords)

        var results: [JobBoardFilteredPosting] = []

        for posting in postings {
            let slug = posting.companySlug.lowercased()
            guard companySlugs.contains(slug) else { continue }

            if !criteria.showClosed {
                guard posting.isActive, posting.closedAt == nil else { continue }
            }
            if JobBoardOpeningsState.isPostingHidden(companySlug: slug, externalPath: posting.externalPath) {
                continue
            }
            if criteria.closingSoonOnly {
                guard let deadline = posting.deadlineAt else { continue }
                let days = Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: deadline)
                ).day ?? 99
                if days > 7 { continue }
            }
            if !JobBoardPostingParsing.matchesDaysPostedFilter(posting, filter: criteria.daysPostedFilter) {
                continue
            }

            let path = posting.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matchScore = matchScoresByPath["\(slug)|\(path)"]

            if let minScore = criteria.minMatchScore {
                guard let matchScore, matchScore >= minScore else { continue }
            }

            if criteria.remoteOnly, !looksRemote(posting) { continue }

            if !matchesTokenGroup(smartTokens, posting: posting) { continue }
            if !jobTypeTokens.isEmpty, !matchesJobTypeTokens(jobTypeTokens, posting: posting) { continue }
            if !scheduleTokens.isEmpty, !matchesScheduleTokens(scheduleTokens, posting: posting) { continue }
            if !locationTokens.isEmpty, !matchesLocationTokens(locationTokens, posting: posting) { continue }

            if !inlineSearch.isEmpty {
                let hay = searchableHaystack(posting).lowercased()
                guard hay.contains(inlineSearch) else { continue }
            }

            let semantic = semanticScore(queryEmbedding: queryEmbedding, postingEmbedding: postingEmbeddings[posting.id])
            let matchComponent = Double(matchScore ?? 0) / 100.0
            let relevance: Double
            if criteria.hasSmartRanking || queryEmbedding != nil {
                if matchScore != nil {
                    relevance = semantic * 0.55 + matchComponent * 0.45
                } else {
                    relevance = semantic
                }
            } else {
                relevance = matchComponent
            }

            results.append(JobBoardFilteredPosting(posting: posting, relevanceScore: relevance, matchScore: matchScore))
        }

        switch sortOrder {
        case .relevance:
            results.sort {
                if $0.relevanceScore != $1.relevanceScore { return $0.relevanceScore > $1.relevanceScore }
                return JobBoardPostingParsing.sortDate(for: $0.posting) > JobBoardPostingParsing.sortDate(for: $1.posting)
            }
        case .matchScore:
            results.sort {
                let l = $0.matchScore ?? -1
                let r = $1.matchScore ?? -1
                if l != r { return l > r }
                return $0.relevanceScore > $1.relevanceScore
            }
        case .newest:
            results.sort {
                JobBoardPostingParsing.sortDate(for: $0.posting) > JobBoardPostingParsing.sortDate(for: $1.posting)
            }
        case .title:
            results.sort { ($0.posting.title ?? "") < ($1.posting.title ?? "") }
        }

        return results
    }

    @MainActor
    static func buildMatchScoreIndex(
        postings: [JobBoardPosting],
        collegePersistence: CollegePersistence,
        resumeHash: String?
    ) -> [String: Int] {
        var index: [String: Int] = [:]
        let slugs = Set(postings.map { $0.companySlug.lowercased() })
        for slug in slugs {
            guard let matches = try? collegePersistence.careerRepository.fetchRecommendedMatches(companySlug: slug)
            else { continue }
            for match in matches where match.recommendedForPosting {
                let path = match.postingExternalPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { continue }
                guard JobBoardMatchEligibility.isMatchCacheValid(
                    match: match,
                    postingDescriptionHash: postings.first(where: { $0.externalPath == path })?.descriptionHash,
                    resumeParsedTextHash: resumeHash
                ) else { continue }
                index["\(slug)|\(path)"] = match.overallScore
            }
        }
        return index
    }

    static func embedQueryOffMain(_ query: String) async -> [Float]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await CareerNLSemanticEmbedding.embed(trimmed)
    }

    private static let maxConcurrentEmbeddings = 4

    static func embedPostingsOffMain(_ snapshots: [JobBoardPostingEmbeddingSnapshot]) async -> [UUID: [Float]] {
        await withTaskGroup(of: (UUID, [Float]?).self) { group in
            var iterator = snapshots.makeIterator()
            var inFlight = 0
            var result: [UUID: [Float]] = [:]

            func enqueueNext() {
                guard let snapshot = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    guard !snapshot.summaryText.isEmpty else { return (snapshot.id, nil) }
                    let vector = await CareerNLSemanticEmbedding.embed(snapshot.summaryText)
                    return (snapshot.id, vector)
                }
            }

            for _ in 0..<min(maxConcurrentEmbeddings, snapshots.count) {
                enqueueNext()
            }

            for await (id, vector) in group {
                inFlight -= 1
                if let vector { result[id] = vector }
                enqueueNext()
            }
            return result
        }
    }

    static func embeddingSnapshots(from postings: [JobBoardPosting]) -> [JobBoardPostingEmbeddingSnapshot] {
        postings.map { posting in
            JobBoardPostingEmbeddingSnapshot(id: posting.id, summaryText: postingSummary(posting))
        }
    }

  // MARK: - Helpers

    private static func semanticScore(queryEmbedding: [Float]?, postingEmbedding: [Float]?) -> Double {
        guard let queryEmbedding, let postingEmbedding else { return 0 }
        let cosine = CareerNLSemanticEmbedding.cosineSimilarity(queryEmbedding, postingEmbedding)
        return Double(max(0, min(1, cosine)))
    }

    private static func postingSummary(_ posting: JobBoardPosting) -> String {
        [
            posting.title,
            posting.jobTypeText,
            posting.timeType,
            posting.locationText,
            posting.workModel,
            snippet(posting.jobDescriptionText, limit: 600),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private static func snippet(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit))
    }

    private static func searchableHaystack(_ posting: JobBoardPosting) -> String {
        [
            posting.title,
            posting.displayJobId,
            posting.locationText,
            posting.jobTypeText,
            posting.timeType,
            posting.workModel,
            snippet(posting.jobDescriptionText, limit: 1200),
            snippet(posting.requirementsText, limit: 800),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func tokenSet(from values: [String]) -> Set<String> {
        Set(
            values
                .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) }
                .map(String.init)
                .filter { $0.count > 2 }
        )
    }

    private static func matchesTokenGroup(_ tokens: Set<String>, posting: JobBoardPosting) -> Bool {
        guard !tokens.isEmpty else { return true }
        let hay = searchableHaystack(posting).lowercased()
        let matched = tokens.filter { hay.contains($0) }
        return Double(matched.count) / Double(tokens.count) >= 0.35
    }

    private static func matchesJobTypeTokens(_ tokens: Set<String>, posting: JobBoardPosting) -> Bool {
        let hay = [posting.jobTypeText, posting.timeType, posting.title]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return tokens.contains { hay.contains($0) }
    }

    private static func matchesScheduleTokens(_ tokens: Set<String>, posting: JobBoardPosting) -> Bool {
        let hay = [posting.timeType, posting.workModel, posting.locationText, posting.title]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return tokens.contains { hay.contains($0) }
    }

    private static func matchesLocationTokens(_ tokens: Set<String>, posting: JobBoardPosting) -> Bool {
        let locations = JobBoardPostingParsing.filterLocations(
            locationText: posting.locationText,
            locationsFilterText: posting.locationsFilterText,
            externalPath: posting.externalPath
        )
        let hay = (locations + [posting.locationText ?? ""])
            .joined(separator: " ")
            .lowercased()
        return tokens.contains { hay.contains($0) }
    }

    private static func looksRemote(_ posting: JobBoardPosting) -> Bool {
        let hay = [posting.locationText, posting.workModel, posting.timeType, posting.title]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return hay.contains("remote") && !hay.contains("no remote") && !hay.contains("not remote")
    }
}
