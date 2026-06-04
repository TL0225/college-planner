// AssistantGemmaStreamFilter.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantGemmaStreamFilter.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Strips common Gemma “thinking” / scratch delimiters from streamed tokens before UI or parsers see them.
enum AssistantGemmaStreamFilter {
    static func stripThinkNoise(_ chunk: String) -> String {
        var s = chunk
        let pairs: [(String, String)] = [
            ("<think>", "</think>"),
            ("<thinking>", "</thinking>"),
        ]
        for (open, close) in pairs {
            if s.contains(open) {
                s = s.replacingOccurrences(of: open, with: "")
            }
            if s.contains(close) {
                s = s.replacingOccurrences(of: close, with: "")
            }
        }
        return s
    }
}
