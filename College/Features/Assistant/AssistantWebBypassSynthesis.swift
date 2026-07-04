// AssistantWebBypassSynthesis.swift
// Feature: Assistant
// Purpose: Shared web-bypass synthesis context (Ship C).

import Foundation

enum AssistantWebBypassSynthesis {
    static func toolContextBlock(
        webQuery: String,
        sources: [AssistantReplySource],
        fetchContext: String?
    ) -> String {
        let sourceLines = sources.prefix(6).enumerated().map { idx, source in
            var line = "\(idx + 1). \(source.title)"
            if let url = source.url, !url.isEmpty { line += " (\(url))" }
            if let snippet = source.snippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                line += "\n   \(snippet)"
            }
            return line
        }
        var block = """
Web search evidence for "\(webQuery)":
\(sourceLines.joined(separator: "\n"))

\(AssistantVoiceGuide.academicAdvisorTone)
Write a concise narrative answer grounded in the evidence above. Do not invent facts beyond snippets or fetched page text. Mention when evidence is incomplete.
"""
        if let fetchContext {
            block += "\n\n\(fetchContext)"
        }
        return block
    }

    static func linkListFallback(webQuery: String, sources: [AssistantReplySource]) -> String {
        let fallbackLines = sources.prefix(6).enumerated().map { idx, source in
            let urlText = source.url ?? ""
            return "\(idx + 1). \(source.title)\(urlText.isEmpty ? "" : " - \(urlText)")"
        }
        return """
I found web results for "\(webQuery)", but could not finish a full synthesis.

\(fallbackLines.joined(separator: "\n"))

Review the sources below and verify important facts with official pages.
"""
    }
}
