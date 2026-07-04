// AssistantISO8601Parsing.swift
// Feature: Assistant
// Purpose: Shared ISO8601 date parsing for tool arguments and pending actions.

import Foundation

enum AssistantISO8601Parsing {
    static func date(from raw: String) -> Date? {
        let fullFormatter = ISO8601DateFormatter()
        fullFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fullFormatter.date(from: raw) {
            return value
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: raw)
    }
}
