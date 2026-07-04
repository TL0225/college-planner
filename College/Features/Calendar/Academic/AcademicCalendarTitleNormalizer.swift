// AcademicCalendarTitleNormalizer.swift
// Feature: Calendar
// Purpose: One-line title cleanup and fuzzy matching helpers.

import Foundation

enum AcademicCalendarTitleNormalizer {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "to", "from", "for", "and", "or", "on", "in", "at", "by"
    ]

    private static let synonymMap: [String: String] = [
        "withdrawal": "withdraw",
        "withdrawing": "withdraw",
        "classes": "class",
        "university": "school",
        "commencement": "graduation"
    ]

    static func oneLineTitle(_ raw: String, maxLength: Int = 120) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPunctuation = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".;:"))
        if trimmedPunctuation.count <= maxLength { return trimmedPunctuation }
        let idx = trimmedPunctuation.index(trimmedPunctuation.startIndex, offsetBy: maxLength)
        return String(trimmedPunctuation[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeTitle(_ raw: String) -> String {
        let oneLine = oneLineTitle(raw)
        let lowered = oneLine.lowercased()
        let stripped = lowered.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        let tokens = stripped
            .split(separator: " ")
            .map(String.init)
            .map { synonymMap[$0] ?? $0 }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return tokens.joined(separator: " ")
    }

    static func identitySignature(title: String, startDay: String) -> String {
        "\(normalizeTitle(title))|\(startDay)"
    }

    static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Set(normalizeTitle(lhs).split(separator: " ").map(String.init))
        let b = Set(normalizeTitle(rhs).split(separator: " ").map(String.init))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    static func areNearDuplicates(_ lhs: String, _ rhs: String, threshold: Double = 0.72) -> Bool {
        titleSimilarity(lhs, rhs) >= threshold
    }
}
