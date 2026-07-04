// AssistantMessageFormatting.swift
// Feature: Assistant
// Purpose: Render guided-response emphasis and paragraph breaks in transcript bubbles.

import Foundation

enum AssistantMessageFormatting {
    /// Splits on blank lines, then applies inline Markdown (**bold**, _italic_) per paragraph.
    static func paragraphs(_ raw: String) -> [AttributedString] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { attributedInline($0) }
    }

    static func attributedInline(_ raw: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}
