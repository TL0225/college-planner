// AssistantLogRedactor.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantLogRedactor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum AssistantLogRedactor {
    /// Best-effort redaction for intelligence-category logs before they are persisted locally.
    static func redactForLog(_ message: String) -> String {
        var s = message
        s = replacing(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: s, with: "[redacted-email]", options: .caseInsensitive)
        s = replacing(pattern: #"\b\d[\d\s\-]{10,}\d\b"#, in: s, with: "[redacted-digits]")
        s = replacing(pattern: #"\b\d{3}-\d{2}-\d{4}\b"#, in: s, with: "[redacted-ssn]")
        s = replacing(pattern: #"\b\d{8,9}\b"#, in: s, with: "[redacted-student-id]")
        s = replacing(pattern: #"(?i)\b(fsa id|password|passcode|pin)\s*[:=]\s*\S+"#, in: s, with: "[redacted-secret]")
        s = replacing(pattern: #"(?i)\b(sai|efc|award|grant|loan|balance)\s*[:=]\s*\$?\d[\d,]*(\.\d{2})?\b"#, in: s, with: "[redacted-aid-amount]")
        return s
    }

    private static func replacing(
        pattern: String,
        in input: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        return re.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}
