// JobBoardPostingParsing.swift
// Feature: Career
// Purpose: Career module — LocationFilterOption.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Normalizes Workday list/detail location and posting-date fields for display, filtering, and sorting.
enum JobBoardPostingParsing {
    private static let aggregateLocationPattern = try? NSRegularExpression(
        pattern: #"^\d+\s+Locations?$"#,
        options: [.caseInsensitive]
    )
    private static let daysAgoPattern = try? NSRegularExpression(
        pattern: #"(\d+)\s+days?\s+ago"#,
        options: [.caseInsensitive]
    )
    private static let locationsFilterSeparator = ";"

    struct LocationFilterOption: Identifiable, Hashable, Sendable {
        /// Stable key for selection and posting matching (`locationNormalizationKey`).
        let id: String
        let displayLabel: String
        let jobCount: Int
    }

    // MARK: - Location

    static func isAggregateLocationCount(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return aggregateLocationPattern?.firstMatch(in: text, range: range) != nil
    }

    static func locationSlug(from externalPath: String?) -> String? {
        guard let externalPath else { return nil }
        let parts = externalPath.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0].lowercased() == "job" else { return nil }
        let slug = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? nil : slug
    }

    static func humanizeLocationSlug(_ slug: String) -> String {
        slug
            .replacingOccurrences(of: "---", with: " - ")
            .replacingOccurrences(of: "--", with: ", ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Primary label for list rows: real location text, or slug from `externalPath` when Workday returns "N Locations".
    static func displayLocation(listText: String?, externalPath: String?) -> String? {
        let trimmed = listText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, !isAggregateLocationCount(trimmed) {
            return trimmed
        }
        if let slug = locationSlug(from: externalPath) {
            return humanizeLocationSlug(slug)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func joinFilterLocations(_ locations: [String]) -> String? {
        let options = buildLocationFilterOptions(from: locations)
        guard !options.isEmpty else { return nil }
        return options.map(\.displayLabel).joined(separator: locationsFilterSeparator)
    }

    static func splitFilterLocations(_ stored: String?) -> [String] {
        guard let stored, !stored.isEmpty else { return [] }
        return stored
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Collapses variants like "USA Remote" and "USA - Remote" to the same filter bucket.
    static func locationNormalizationKey(_ text: String) -> String {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s*[-–—]\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }

    static func prefersCanonicalLocationLabel(_ candidate: String, over existing: String) -> Bool {
        let candidateScore = canonicalLocationLabelScore(candidate)
        let existingScore = canonicalLocationLabelScore(existing)
        if candidateScore != existingScore { return candidateScore > existingScore }
        return candidate.count > existing.count
    }

    private static func canonicalLocationLabelScore(_ label: String) -> Int {
        var score = 0
        if label.contains(" - ") { score += 4 }
        if label.contains(",") { score += 1 }
        if label.range(of: #"\d+\s+Locations?"#, options: .regularExpression) == nil { score += 2 }
        return score
    }

    static func buildLocationFilterOptions(from labels: [String]) -> [LocationFilterOption] {
        struct Bucket {
            var label: String
            var count: Int
        }
        var buckets: [String: Bucket] = [:]
        for raw in labels {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isAggregateLocationCount(trimmed) else { continue }
            let key = locationNormalizationKey(trimmed)
            guard !key.isEmpty else { continue }
            if var bucket = buckets[key] {
                bucket.count += 1
                if prefersCanonicalLocationLabel(trimmed, over: bucket.label) {
                    bucket.label = trimmed
                }
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(label: trimmed, count: 1)
            }
        }
        return buckets.map { key, bucket in
            LocationFilterOption(id: key, displayLabel: bucket.label, jobCount: bucket.count)
        }
        .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }

    static func filterLocations(
        locationText: String?,
        locationsFilterText: String?,
        externalPath: String?
    ) -> [String] {
        let stored = splitFilterLocations(locationsFilterText)
        if !stored.isEmpty { return stored }

        if let display = displayLocation(listText: locationText, externalPath: externalPath) {
            return [display]
        }
        return []
    }

    static func postingMatchesLocationFilter(
        locationText: String?,
        locationsFilterText: String?,
        externalPath: String?,
        filterKey: String?
    ) -> Bool {
        guard let filterKey, !filterKey.isEmpty else { return true }
        let keys = filterLocations(
            locationText: locationText,
            locationsFilterText: locationsFilterText,
            externalPath: externalPath
        ).map { locationNormalizationKey($0) }
        return keys.contains(filterKey)
    }

    static func resolvedFilterLocations(
        listText: String?,
        externalPath: String?,
        detailPrimary: String?,
        detailAdditional: [String]?
    ) -> [String] {
        if let detailAdditional, !detailAdditional.isEmpty {
            var all = Set<String>()
            if let primary = detailPrimary?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
                all.insert(primary)
            }
            for item in detailAdditional {
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { all.insert(trimmed) }
            }
            return all.sorted()
        }

        if let primary = detailPrimary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !primary.isEmpty, !isAggregateLocationCount(primary) {
            return [primary]
        }

        if let display = displayLocation(listText: listText, externalPath: externalPath) {
            return [display]
        }
        return []
    }

    static func detailLocationDisplay(
        listText: String?,
        externalPath: String?,
        primary: String?,
        additional: [String]?
    ) -> String? {
        if let primary = primary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !primary.isEmpty, !isAggregateLocationCount(primary) {
            if let additional, additional.count > 1 {
                return "\(primary) (\(additional.count) locations)"
            }
            return primary
        }
        return displayLocation(listText: listText, externalPath: externalPath)
    }

    // MARK: - Posted date

    static func parsePostedOn(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let lower = text.lowercased()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        if lower.contains("today") {
            return startOfToday
        }
        if lower.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: startOfToday)
        }
        if lower.contains("30+") || lower.contains("30 +") {
            return calendar.date(byAdding: .day, value: -30, to: startOfToday)
        }

        if let daysAgoPattern {
            let range = NSRange(lower.startIndex..., in: lower)
            if let match = daysAgoPattern.firstMatch(in: lower, range: range),
               match.numberOfRanges > 1,
               let dayRange = Range(match.range(at: 1), in: lower),
               let days = Int(lower[dayRange]) {
                return calendar.date(byAdding: .day, value: -days, to: startOfToday)
            }
        }

        if let iso = parseISODate(text) {
            return iso
        }

        return nil
    }

    static func parseISODate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZ",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }
}
