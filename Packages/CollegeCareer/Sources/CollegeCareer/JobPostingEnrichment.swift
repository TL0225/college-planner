// JobPostingEnrichment.swift
// Feature: Career
// Purpose: Career module — JobPostingEnrichment.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit

public enum JobPostingEnrichment {
    /// Annual salary in whole dollars (not cents) for min/max.
    public static func extractSalaryRange(from text: String) -> (min: Int, max: Int)? {
        let patterns: [String] = [
            #"\$\s*([\d,]+(?:\.\d{2})?)\s*(?:k|K)?\s*[-–—to]+\s*\$\s*([\d,]+(?:\.\d{2})?)\s*(?:k|K)?"#,
            #"(?:salary|pay|compensation)[:\s]+\$\s*([\d,]+)\s*[-–—]+\s*\$\s*([\d,]+)"#,
            #"up\s+to\s+\$\s*([\d,]+(?:\.\d{2})?)\s*(?:k|K)?"#,
            #"\$\s*([\d,]+)\s*/\s*hr"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, groups: 2) {
                if pattern.contains("up to"), let high = parseAmount(match[0]) {
                    return (min: Int(Double(high) * 0.85), max: high)
                }
                if pattern.contains("/ hr"), let hourly = parseAmount(match[0]) {
                    let annual = hourly * 2080
                    return (min: annual, max: annual)
                }
                if let a = parseAmount(match[0]), let b = parseAmount(match[1]) {
                    return (min: min(a, b), max: max(a, b))
                }
            }
        }
        return nil
    }

    public static func extractDeadline(from text: String) -> Date? {
        let phrases = [
            #"apply\s+by\s+([A-Za-z]+\s+\d{1,2},?\s+\d{4})"#,
            #"deadline[:\s]+([A-Za-z]+\s+\d{1,2},?\s+\d{4})"#,
            #"applications?\s+close[s]?\s+(?:on\s+)?([A-Za-z]+\s+\d{1,2},?\s+\d{4})"#,
            #"position\s+closes?\s+(?:on\s+)?([A-Za-z]+\s+\d{1,2},?\s+\d{4})"#,
            #"closing\s+date[:\s]+([A-Za-z]+\s+\d{1,2},?\s+\d{4})"#,
        ]
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.locale = Locale(identifier: "en_US_POSIX")
            f1.dateFormat = "MMMM d, yyyy"
            let f2 = DateFormatter()
            f2.locale = Locale(identifier: "en_US_POSIX")
            f2.dateFormat = "MMMM d yyyy"
            return [f1, f2]
        }()

        for pattern in phrases {
            if let groups = firstMatch(pattern: pattern, in: text, groups: 1),
               let raw = groups.first {
                for f in formatters {
                    if let date = f.date(from: raw.trimmingCharacters(in: .whitespaces)) {
                        return date
                    }
                }
            }
        }
        return nil
    }

    public static func descriptionHash(_ plain: String) -> String {
        let data = Data(plain.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func appendChangeLog(existing: String?, summary: String) -> String {
        let line = "\(Self.todayStamp()): \(summary)"
        if let existing, !existing.isEmpty {
            return existing + "\n" + line
        }
        return line
    }

    public static func changeSummary(oldHash: String?, newHash: String, oldSalary: String?, newMin: Int?, newMax: Int?) -> String? {
        guard oldHash != newHash else { return nil }
        if oldSalary == nil, newMin != nil { return "Salary range added" }
        return "Description updated"
    }

    public static func formatSalaryRange(min: Int, max: Int) -> String {
        func fmt(_ v: Int) -> String {
            if v >= 1000, v % 1000 == 0 { return "$\(v / 1000)K" }
            let nf = NumberFormatter()
            nf.numberStyle = .currency
            nf.maximumFractionDigits = 0
            return nf.string(from: NSNumber(value: v)) ?? "$\(v)"
        }
        if min == max { return "\(fmt(min)) / year" }
        return "\(fmt(min)) – \(fmt(max)) / year"
    }

    public static func deadlineBadgeText(for deadline: Date) -> (text: String, urgent: Bool)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: deadline)
        guard let days = cal.dateComponents([.day], from: start, to: end).day else { return nil }
        if days < 0 { return ("Deadline passed", true) }
        if days == 0 { return ("Deadline today", true) }
        if days <= 3 { return ("Deadline in \(days) day\(days == 1 ? "" : "s")", true) }
        if days <= 7 { return ("Deadline in \(days) days", false) }
        return nil
    }

    private static func todayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func parseAmount(_ raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        var multiplier = 1
        if s.lowercased().hasSuffix("k") {
            multiplier = 1000
            s = String(s.dropLast())
        }
        if let d = Double(s) {
            return Int(d * Double(multiplier))
        }
        return nil
    }

    private static func firstMatch(pattern: String, in text: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var result: [String] = []
        for i in 1...groups {
            if match.numberOfRanges > i, let r = Range(match.range(at: i), in: text) {
                result.append(String(text[r]))
            }
        }
        return result.isEmpty ? nil : result
    }
}
