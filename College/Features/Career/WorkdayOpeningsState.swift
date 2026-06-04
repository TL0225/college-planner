// WorkdayOpeningsState.swift
// Feature: Career
// Purpose: Career module — WorkdayOpeningsState.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Per-posting "seen" state and per-company last-visit timestamps for Openings badges.
enum WorkdayOpeningsState {
    private static let seenKeysDefaultsKey = "workday.seenPostingKeys"
    private static let hiddenKeysDefaultsKey = "workday.hiddenPostingKeys"
    private static let maxStoredPostingKeys = 2_000
    nonisolated(unsafe) private static var cachedSeenKeys: Set<String>?
    nonisolated(unsafe) private static var cachedHiddenKeys: Set<String>?

    static func postingKey(companySlug: String, externalPath: String) -> String {
        "\(companySlug)|\(externalPath)"
    }

    private static func companyViewedKey(slug: String) -> String {
        "workday.companyViewedAt.\(slug)"
    }

    static func markPostingSeen(companySlug: String, externalPath: String?) {
        guard let externalPath, !externalPath.isEmpty else { return }
        var keys = seenKeys()
        keys.insert(postingKey(companySlug: companySlug, externalPath: externalPath))
        persistSeenKeys(keys)
    }

    static func isPostingSeen(companySlug: String, externalPath: String?) -> Bool {
        guard let externalPath, !externalPath.isEmpty else { return false }
        return seenKeys().contains(postingKey(companySlug: companySlug, externalPath: externalPath))
    }

    static func markCompanyViewed(slug: String) {
        UserDefaults.standard.set(Date(), forKey: companyViewedKey(slug: slug))
    }

    static func lastCompanyViewedAt(slug: String) -> Date? {
        UserDefaults.standard.object(forKey: companyViewedKey(slug: slug)) as? Date
    }

    private static func seenKeys() -> Set<String> {
        if let cachedSeenKeys { return cachedSeenKeys }
        let keys = Set(UserDefaults.standard.stringArray(forKey: seenKeysDefaultsKey) ?? [])
        cachedSeenKeys = keys
        return keys
    }

    static func hidePosting(companySlug: String, externalPath: String?) {
        guard let externalPath, !externalPath.isEmpty else { return }
        var keys = hiddenKeys()
        keys.insert(postingKey(companySlug: companySlug, externalPath: externalPath))
        persistHiddenKeys(keys)
    }

    static func isPostingHidden(companySlug: String, externalPath: String?) -> Bool {
        guard let externalPath, !externalPath.isEmpty else { return false }
        return hiddenKeys().contains(postingKey(companySlug: companySlug, externalPath: externalPath))
    }

    private static func hiddenKeys() -> Set<String> {
        if let cachedHiddenKeys { return cachedHiddenKeys }
        let keys = Set(UserDefaults.standard.stringArray(forKey: hiddenKeysDefaultsKey) ?? [])
        cachedHiddenKeys = keys
        return keys
    }

    private static func persistSeenKeys(_ keys: Set<String>) {
        let trimmed = trimKeysIfNeeded(keys)
        cachedSeenKeys = trimmed
        UserDefaults.standard.set(Array(trimmed), forKey: seenKeysDefaultsKey)
    }

    private static func persistHiddenKeys(_ keys: Set<String>) {
        let trimmed = trimKeysIfNeeded(keys)
        cachedHiddenKeys = trimmed
        UserDefaults.standard.set(Array(trimmed), forKey: hiddenKeysDefaultsKey)
    }

    private static func trimKeysIfNeeded(_ keys: Set<String>) -> Set<String> {
        guard keys.count > maxStoredPostingKeys else { return keys }
        return Set(keys.sorted().suffix(maxStoredPostingKeys))
    }

    @MainActor
    static func newCountForCompany(slug: String) -> Int {
        let repo = AppDataStore.shared.careerRepository
        guard let postings = try? repo.fetchCompanyPostings(companySlug: slug) else { return 0 }
        return newCount(for: postings, companySlug: slug)
    }

    static func newCount(for postings: [WorkdayJobPosting], companySlug: String) -> Int {
        if let since = lastCompanyViewedAt(slug: companySlug) {
            return postings.filter { posting in
                guard let first = posting.firstSeenAt else { return false }
                return first > since
                    && !isPostingSeen(companySlug: companySlug, externalPath: posting.externalPath)
            }.count
        }

        let cutoff = Date().addingTimeInterval(-WorkdayJobBoardThresholds.newPostingMaxAge)
        return postings.filter { posting in
            guard let first = posting.firstSeenAt, first >= cutoff else { return false }
            return !isPostingSeen(companySlug: companySlug, externalPath: posting.externalPath)
        }.count
    }
}

enum WorkdayJobListSort: String, CaseIterable, Identifiable {
    case newest
    case title
    case jobID

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: return "Newest"
        case .title: return "Title"
        case .jobID: return "Job ID"
        }
    }
}

enum WorkdayDaysPostedFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek
    case thirtyPlusDays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "Any time"
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .thirtyPlusDays: return "30+ days"
        }
    }
}
