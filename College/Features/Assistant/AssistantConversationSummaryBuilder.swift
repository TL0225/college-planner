// AssistantConversationSummaryBuilder.swift
// Builds recent-conversation blocks for planner context (testable).

import Foundation

enum AssistantConversationSummaryBuilder {

    static func makeSummary(
        messages: [AssistantMessage],
        currentPrompt: String,
        recentMessageCount: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d h:mm a"
        let recent = messages.suffix(recentMessageCount)
        guard !recent.isEmpty else { return "No earlier conversation in this session." }
        let lines = recent.map { message in
            let speaker = message.isUser ? "User" : message.role.rawValue
            let safeText: String = {
                let t = message.text
                if t.count <= 300 { return t }
                return String(t.prefix(300)) + "..."
            }()
            return "[\(formatter.string(from: message.timestamp))] \(speaker): \(safeText)"
        }
        if let last = lines.last, last.contains(currentPrompt) {
            return lines.joined(separator: "\n")
        }
        return (lines + ["[Now] User: \(currentPrompt)"]).joined(separator: "\n")
    }
}
