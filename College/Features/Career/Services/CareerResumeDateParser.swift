// CareerResumeDateParser.swift
// Feature: Career
// Purpose: Extract employment date ranges from resume heading lines (handles multi-dash titles).

import Foundation

enum CareerResumeDateParser {
    private static let monthPattern =
        #"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"#

    /// Parses the rightmost date range in a heading like
    /// `Cybersecurity Analyst Intern – Insmed – Remote June 2025 – August 2025`.
    static func parseDateRange(from heading: String) -> (start: Date, end: Date)? {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = lastMonthYearRange(in: trimmed) { return range }
        if let range = lastYearOnlyRange(in: trimmed) { return range }
        return nil
    }

    static func yearsSinceEnd(heading: String, now: Date = Date()) -> Int? {
        guard let range = parseDateRange(from: heading) else { return nil }
        let lower = heading.lowercased()
        if lower.contains("present") || lower.contains("current") { return 0 }
        let years = Calendar.current.dateComponents([.year], from: range.end, to: now).year ?? 0
        return max(0, years)
    }

    private static func lastMonthYearRange(in text: String) -> (start: Date, end: Date)? {
        let pattern = """
        (?i)(\(monthPattern))\\s+(\\d{4})\\s*[–\\-—]\\s*(?:(\(monthPattern))\\s+(\\d{4})|present|current|now)
        """
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard let last = matches.last else { return nil }
        return dateRange(from: last, in: text)
    }

    private static func lastYearOnlyRange(in text: String) -> (start: Date, end: Date)? {
        let pattern = #"(?i)(\d{4})\s*[–\-—]\s*(\d{4}|present|current|now)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard let last = matches.last else { return nil }

        guard last.numberOfRanges >= 3,
              let startYearRange = Range(last.range(at: 1), in: text),
              let endRange = Range(last.range(at: 2), in: text),
              let startYear = Int(text[startYearRange])
        else { return nil }

        let endToken = text[endRange].lowercased()
        let end: Date
        if endToken.contains("present") || endToken.contains("current") || endToken.contains("now") {
            end = Date()
        } else if let endYear = Int(endToken) {
            end = partialDate(month: 12, year: endYear) ?? Date()
        } else {
            return nil
        }

        guard let start = partialDate(month: 1, year: startYear), end >= start else { return nil }
        return (start, end)
    }

    private static func dateRange(from match: NSTextCheckingResult, in text: String) -> (start: Date, end: Date)? {
        guard match.numberOfRanges >= 3,
              let startMonthRange = Range(match.range(at: 1), in: text),
              let startYearRange = Range(match.range(at: 2), in: text),
              let startYear = Int(text[startYearRange])
        else { return nil }

        let startMonth = monthNumber(from: String(text[startMonthRange]))
        guard let start = partialDate(month: startMonth, year: startYear) else { return nil }

        if match.numberOfRanges >= 5,
           match.range(at: 3).location != NSNotFound,
           let endMonthRange = Range(match.range(at: 3), in: text),
           let endYearRange = Range(match.range(at: 4), in: text),
           let endYear = Int(text[endYearRange]) {
            let endMonth = monthNumber(from: String(text[endMonthRange]))
            guard let end = partialDate(month: endMonth, year: endYear), end >= start else { return nil }
            return (start, end)
        }

        if match.numberOfRanges >= 3,
           let endTokenRange = Range(match.range(at: 3), in: text) {
            let endToken = text[endTokenRange].lowercased()
            if endToken.contains("present") || endToken.contains("current") || endToken.contains("now") {
                return (start, Date())
            }
        }
        return nil
    }

    private static func monthNumber(from token: String) -> Int {
        let lower = token.lowercased()
        if lower.hasPrefix("jan") { return 1 }
        if lower.hasPrefix("feb") { return 2 }
        if lower.hasPrefix("mar") { return 3 }
        if lower.hasPrefix("apr") { return 4 }
        if lower == "may" { return 5 }
        if lower.hasPrefix("jun") { return 6 }
        if lower.hasPrefix("jul") { return 7 }
        if lower.hasPrefix("aug") { return 8 }
        if lower.hasPrefix("sep") { return 9 }
        if lower.hasPrefix("oct") { return 10 }
        if lower.hasPrefix("nov") { return 11 }
        if lower.hasPrefix("dec") { return 12 }
        return 6
    }

    static func partialDate(month: Int, year: Int) -> Date? {
        guard year > 1950, year < 2100 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components)
    }

    static func parsePartialDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["MM/yyyy", "M/yyyy", "MMM yyyy", "MMMM yyyy", "yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        if let year = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).last,
           year > 1950, year < 2100 {
            return partialDate(month: 6, year: year)
        }
        return nil
    }
}
