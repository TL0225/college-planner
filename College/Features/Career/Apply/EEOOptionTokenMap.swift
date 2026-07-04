// EEOOptionTokenMap.swift
// Feature: Career / Apply
// Purpose: Platform EEO token maps — no fuzzy matching (V2 writes deferred in V1).

import Foundation

enum EEOOptionTokenMap {
    static let declineTokens: Set<String> = [
        "decline", "decline_to_state", "prefer_not", "prefer not", "undisclosed", "do not wish"
    ]

    static func normalizedToken(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchesDecline(_ optionText: String) -> Bool {
        let token = normalizedToken(optionText)
        return declineTokens.contains(token)
    }
}
