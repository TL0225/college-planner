// AssistantSessionContinuity.swift
// Feature: Assistant
// Purpose: Local cross-session topic memory (last 3 intents/queries).

import Foundation

enum AssistantSessionContinuity {
    private static let storageKey = "assistant.memory.recentTopics.v1"
    private static let maxTopics = 3

    private struct TopicRow: Codable, Sendable {
        let intent: String
        let querySnippet: String
        let savedAt: Date
    }

    static func recordTurn(intent: String?, userQuery: String) {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let intentLabel = (intent ?? "general").trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(query.prefix(120))
        var rows = loadRows()
        rows.removeAll { $0.querySnippet.lowercased() == snippet.lowercased() }
        rows.insert(TopicRow(intent: intentLabel, querySnippet: snippet, savedAt: Date()), at: 0)
        if rows.count > maxTopics {
            rows = Array(rows.prefix(maxTopics))
        }
        persist(rows)
    }

    static func openingContextBlock() -> String {
        let rows = loadRows()
        guard !rows.isEmpty else { return "" }
        let lines = rows.enumerated().map { idx, row in
            "\(idx + 1). [\(row.intent)] \(row.querySnippet)"
        }
        return """
        Recent topics from your last sessions (local only):
        \(lines.joined(separator: "\n"))
        """
    }

    static func recentTopicsForTesting() -> [(intent: String, query: String)] {
        loadRows().map { ($0.intent, $0.querySnippet) }
    }

#if DEBUG
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
#endif

    private static func loadRows() -> [TopicRow] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TopicRow].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(_ rows: [TopicRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
