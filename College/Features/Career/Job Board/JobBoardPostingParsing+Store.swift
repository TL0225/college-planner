// JobBoardPostingParsing+Store.swift
// Feature: Career
// Purpose: Career module — JobTypeFilterOption.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension JobBoardPostingParsing {
    static func sortDate(for posting: JobBoardPosting) -> Date {
        posting.postedAt
            ?? parsePostedOn(posting.postedOnText)
            ?? posting.firstSeenAt
            ?? .distantPast
    }

    static func daysPostedBucket(for posting: JobBoardPosting) -> JobBoardDaysPostedFilter {
        if let text = posting.postedOnText?.lowercased() {
            if text.contains("today") || text.contains("yesterday") {
                return .today
            }
            if text.contains("30+") || text.contains("30 +") {
                return .thirtyPlusDays
            }
        }

        guard let posted = posting.postedAt ?? parsePostedOn(posting.postedOnText) else {
            return .all
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        if posted >= startOfToday { return .today }

        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
           posted >= weekAgo {
            return .thisWeek
        }

        if let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
           posted < monthAgo {
            return .thirtyPlusDays
        }

        return .all
    }

    static func matchesDaysPostedFilter(
        _ posting: JobBoardPosting,
        filter: JobBoardDaysPostedFilter
    ) -> Bool {
        guard filter != .all else { return true }
        return daysPostedBucket(for: posting) == filter
    }

    static func postingMatchesJobTypeFilter(
        _ posting: JobBoardPosting,
        filterKey: String?
    ) -> Bool {
        guard let filterKey, !filterKey.isEmpty else { return true }
        guard let jobType = posting.jobTypeText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jobType.isEmpty
        else { return false }
        return locationNormalizationKey(jobType) == filterKey
    }

    static func postingMatchesTimeTypeFilter(
        _ posting: JobBoardPosting,
        filterKey: String?
    ) -> Bool {
        guard let filterKey, !filterKey.isEmpty else { return true }
        guard let timeType = posting.timeType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !timeType.isEmpty
        else { return false }
        return locationNormalizationKey(timeType) == filterKey
    }

    struct JobTypeFilterOption: Identifiable, Hashable, Sendable {
        let id: String
        let displayLabel: String
        let jobCount: Int
    }

    struct TimeTypeFilterOption: Identifiable, Hashable, Sendable {
        let id: String
        let displayLabel: String
        let jobCount: Int
    }

    static func buildJobTypeFilterOptions(from labels: [String]) -> [JobTypeFilterOption] {
        buildCountedFilterOptions(from: labels).map {
            JobTypeFilterOption(id: $0.id, displayLabel: $0.displayLabel, jobCount: $0.jobCount)
        }
    }

    static func buildTimeTypeFilterOptions(from labels: [String]) -> [TimeTypeFilterOption] {
        buildCountedFilterOptions(from: labels).map {
            TimeTypeFilterOption(id: $0.id, displayLabel: $0.displayLabel, jobCount: $0.jobCount)
        }
    }

    private struct CountedFilterOption {
        let id: String
        let displayLabel: String
        let jobCount: Int
    }

    private static func buildCountedFilterOptions(from labels: [String]) -> [CountedFilterOption] {
        var buckets: [String: (label: String, count: Int)] = [:]
        for raw in labels {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = locationNormalizationKey(trimmed)
            guard !key.isEmpty else { continue }
            if var bucket = buckets[key] {
                bucket.count += 1
                if prefersCanonicalLocationLabel(trimmed, over: bucket.label) {
                    bucket.label = trimmed
                }
                buckets[key] = bucket
            } else {
                buckets[key] = (trimmed, 1)
            }
        }
        return buckets.map { key, bucket in
            CountedFilterOption(id: key, displayLabel: bucket.label, jobCount: bucket.count)
        }
        .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }
}
