// AssistantConversationMemory.swift
// Feature: Assistant
// Purpose: Assistant module — Row.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Compact, on-device “helpful turn” snippets for cross-session context (UserDefaults, capped).
enum AssistantConversationMemory {
    private static let storageKey = "assistant.memory.helpfulSnippets.v1"
    private static let maxRows = 12
    private static let maxQueryChars = 400
    private static let maxReplyChars = 700

    private struct Row: Codable, Sendable {
        let query: String
        let replySnippet: String
        let savedAt: Date
    }

    static func recordHelpful(userQuery: String, assistantReply: String) {
        let q = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = assistantReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !r.isEmpty else { return }

        let query = String(q.prefix(maxQueryChars))
        let snippet = String(r.prefix(maxReplyChars))
        let normalized = query.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        var rows: [Row] = loadRows()
        rows.removeAll { existing in
            let n = existing.query.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return n == normalized
        }
        rows.insert(Row(query: query, replySnippet: snippet, savedAt: Date()), at: 0)
        if rows.count > maxRows {
            rows = Array(rows.prefix(maxRows))
        }
        persist(rows)
    }

    static func removeHelpfulMatching(query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !normalized.isEmpty else { return }
        var rows = loadRows()
        rows.removeAll { existing in
            let n = existing.query.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return n == normalized
        }
        persist(rows)
    }

    static func contextBlock(charBudget: Int) -> String {
        guard charBudget > 0 else { return "" }
        let rows = loadRows().prefix(8)
        guard !rows.isEmpty else { return "" }

        var lines: [String] = ["Saved helpful Q&A snippets (local, from thumbs-up in past sessions):"]
        var used = lines.joined(separator: "\n").count

        for row in rows {
            let piece = "- Q: \(row.query)\n  A: \(row.replySnippet)"
            if used + piece.count + 1 > charBudget { break }
            lines.append(piece)
            used += piece.count + 1
        }
        return lines.joined(separator: "\n")
    }

    private static func loadRows() -> [Row] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Row].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(_ rows: [Row]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
