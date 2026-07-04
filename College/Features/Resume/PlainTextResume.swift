// PlainTextResume.swift
// Feature: Resume
// Purpose: Convert Typst source to plain text for the dev fallback PDF renderer.

import Foundation

enum PlainTextResume {
    static func from(_ typstSource: String) -> String {
        var lines: [String] = []
        for rawLine in typstSource.components(separatedBy: .newlines) {
            let line = stripTypstMarkup(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n")
    }

    private static func stripTypstMarkup(_ line: String) -> String {
        var result = line
        let patterns = [
            "#set [^\\n]*",
            "#text\\([^\\)]*\\)\\[([^\\]]*)\\]",
            "#link\\([^\\)]*\\)\\[([^\\]]*)\\]",
            "#link\\([^\\)]*\\)",
            "\\\\([#*_@\\[\\]$<>\\\\])",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                if pattern.contains("(") && pattern.contains("\\[") {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: range,
                        withTemplate: "$1"
                    )
                } else {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: range,
                        withTemplate: ""
                    )
                }
            }
        }

        if result.hasPrefix("=") {
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        }
        result = result.replacingOccurrences(of: "*", with: "")
        return result
    }
}
