// DiagnosticsExportRedactor.swift
// Feature: Debug
// Purpose: DG1 — redact home paths, emails, and keychain hints from exported text artifacts.

import Foundation

enum DiagnosticsExportRedactor {
    private static let homePathPattern: NSRegularExpression = {
        let home = NSRegularExpression.escapedPattern(for: FileManager.default.homeDirectoryForCurrentUser.path)
        return try! NSRegularExpression(pattern: home + #"[^\s\"']*"#, options: [])
    }()

    private static let emailPattern = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"(?i)(api[_-]?key|token|password|secret|bearer)\s*[:=]\s*\S+"#
    )

    static func redact(_ text: String, level: DiagnosticsExportLevel) -> String {
        var out = text
        out = replace(homePathPattern, in: out, with: "[REDACTED_PATH]")
        if level == .basic {
            out = replace(emailPattern, in: out, with: "[REDACTED_EMAIL]")
            out = replace(tokenPattern, in: out, with: "$1: [REDACTED]")
        }
        return out
    }

    static func redactedCopy(from source: URL, to destination: URL, level: DiagnosticsExportLevel) throws {
        let ext = source.pathExtension.lowercased()
        let textLike = ["log", "txt", "json", "md", "plist"].contains(ext)
        guard textLike, let data = try? Data(contentsOf: source),
              let text = String(data: data, encoding: .utf8) else {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        let redacted = redact(text, level: level)
        try redacted.write(to: destination, atomically: true, encoding: .utf8)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
