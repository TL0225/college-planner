// CareerATSAdviceValidator.swift
// Feature: Career
// Purpose: Reject generic LLM tips; only surface specific actionable advice.

import Foundation

enum CareerATSAdviceValidator {
    private static let genericPhrases = [
        "add more keywords",
        "tailor your resume",
        "highlight relevant experience",
        "improve your resume",
        "consider adding",
        "make sure to include",
        "you should add",
    ]

    static func validatedTip(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return nil }
        let lower = trimmed.lowercased()
        for phrase in genericPhrases where lower.contains(phrase) {
            return nil
        }
        return trimmed
    }

    static func validatedGapParagraph(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40, trimmed.count <= 600 else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("i am writing to express") || lower.contains("dear hiring manager") {
            return nil
        }
        return trimmed
    }
}
