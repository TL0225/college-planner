// ResumeATSDates.swift
// Feature: Resume
// Purpose: ATS-safe date normalization for apply payloads and builder export.

import Foundation

enum ResumeATSDates {
    /// Normalizes free-form date strings to `MM/YYYY` when possible; preserves Present/Current.
    static func normalizeForATS(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let lower = value.lowercased()
        if lower.contains("present") || lower.contains("current") || lower.contains("now") {
            return "Present"
        }
        if let range = CareerResumeDateParser.parseDateRange(from: value) {
            let endLabel = (lower.contains("present") || lower.contains("current") || lower.contains("now"))
                ? "Present"
                : monthYear(range.end)
            return "\(monthYear(range.start)) – \(endLabel)"
        }
        if let normalized = normalizeMonthYearToken(value) {
            return normalized
        }
        return value
    }

    static func normalizeRangeForATS(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw
            .replacingOccurrences(of: "—", with: "–")
            .split(separator: "–", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else {
            return normalizeForATS(raw)
        }
        let start = normalizeForATS(parts[0]) ?? parts[0]
        let end = normalizeForATS(parts[1]) ?? parts[1]
        return "\(start) – \(end)"
    }

    private static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/yyyy"
        return formatter.string(from: date)
    }

    private static func normalizeMonthYearToken(_ value: String) -> String? {
        let pattern = #"(?i)(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges >= 3,
              let monthRange = Range(match.range(at: 1), in: value),
              let yearRange = Range(match.range(at: 2), in: value)
        else { return nil }

        let monthToken = String(value[monthRange]).lowercased()
        let year = String(value[yearRange])
        let monthNumber = monthIndex(monthToken)
        return String(format: "%02d/%@", monthNumber, year)
    }

    private static func monthIndex(_ token: String) -> Int {
        switch token.prefix(3) {
        case "jan": return 1
        case "feb": return 2
        case "mar": return 3
        case "apr": return 4
        case "may": return 5
        case "jun": return 6
        case "jul": return 7
        case "aug": return 8
        case "sep": return 9
        case "oct": return 10
        case "nov": return 11
        case "dec": return 12
        default: return 1
        }
    }
}
