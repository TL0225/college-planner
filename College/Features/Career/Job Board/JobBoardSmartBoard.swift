// JobBoardSmartBoard.swift
// Feature: Career / Job Board
// Purpose: User-defined boards that combine multiple companies with smart filters.

import Foundation

/// Composite list selection key (`companySlug|externalPath`) for unified multi-company browsing.
enum JobBoardPostingSelectionKey {
    static func tag(companySlug: String, externalPath: String?) -> String {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = (externalPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(slug)|\(path)"
    }

    static func parse(_ tag: String) -> (companySlug: String, externalPath: String)? {
        let parts = tag.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0].lowercased(), parts[1])
    }
}

enum JobBoardSidebarTag: Hashable {
    case company(UUID)
    case smartBoard(UUID)

    private static let companyPrefix = "company:"
    private static let boardPrefix = "board:"

    var storageValue: String {
        switch self {
        case .company(let id): return Self.companyPrefix + id.uuidString
        case .smartBoard(let id): return Self.boardPrefix + id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> JobBoardSidebarTag? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix(companyPrefix) {
            let idString = String(raw.dropFirst(companyPrefix.count))
            guard let id = UUID(uuidString: idString) else { return nil }
            return .company(id)
        }
        if raw.hasPrefix(boardPrefix) {
            let idString = String(raw.dropFirst(boardPrefix.count))
            guard let id = UUID(uuidString: idString) else { return nil }
            return .smartBoard(id)
        }
        return nil
    }
}

/// Structured filter criteria for a smart board (persisted + AI-refined).
struct JobBoardSmartFilterCriteria: Codable, Equatable, Sendable {
    var smartQuery: String = ""
    var keywords: [String] = []
    var requiredSkills: [String] = []
    var jobTypeKeywords: [String] = []
    var scheduleKeywords: [String] = []
    var locationKeywords: [String] = []
    var minMatchScore: Int?
    var daysPostedFilter: JobBoardDaysPostedFilter = .all
    var hideOnBoard: Bool = false
    var showClosed: Bool = false
    var closingSoonOnly: Bool = false
    var remoteOnly: Bool = false

    var hasSmartRanking: Bool {
        !smartQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !keywords.isEmpty
            || !requiredSkills.isEmpty
    }
}

/// AI/heuristic interpretation of a natural-language job search query.
struct JobBoardSmartFilterInterpretation: Codable, Equatable, Sendable {
    var keywords: [String] = []
    var requiredSkills: [String] = []
    var jobTypes: [String] = []
    var scheduleTypes: [String] = []
    var locations: [String] = []
    var minMatchScore: Int?
    var remoteOnly: Bool?
    var explanation: String?

    func merged(into criteria: JobBoardSmartFilterCriteria, query: String) -> JobBoardSmartFilterCriteria {
        var next = criteria
        next.smartQuery = query
        if !keywords.isEmpty { next.keywords = keywords }
        if !requiredSkills.isEmpty { next.requiredSkills = requiredSkills }
        if !jobTypes.isEmpty { next.jobTypeKeywords = jobTypes }
        if !scheduleTypes.isEmpty { next.scheduleKeywords = scheduleTypes }
        if !locations.isEmpty { next.locationKeywords = locations }
        if let minMatchScore { next.minMatchScore = minMatchScore }
        if let remoteOnly { next.remoteOnly = remoteOnly }
        return next
    }
}

struct JobBoardSmartBoard: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var companyIDs: [UUID]
    var criteria: JobBoardSmartFilterCriteria = JobBoardSmartFilterCriteria()
    var sortOrder: JobBoardUnifiedSort = .relevance
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum JobBoardUnifiedSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case relevance
    case matchScore
    case newest
    case title

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relevance: return "Relevance"
        case .matchScore: return "Resume match"
        case .newest: return "Newest"
        case .title: return "Title"
        }
    }
}
