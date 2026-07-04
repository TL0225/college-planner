// AssistantWebPageCache.swift
// Feature: Assistant
// Purpose: URL-keyed page cache with TTL (Ship C).

import Foundation

struct AssistantWebPageCacheEntry: Sendable, Equatable {
    let url: String
    let bodyText: String
    let fetchedAt: Date
    let host: String
}

actor AssistantWebPageCache {
    static let shared = AssistantWebPageCache()

    private var entries: [String: AssistantWebPageCacheEntry] = [:]
    private let policyTTL: TimeInterval = 7 * 86400
    private let genericTTL: TimeInterval = 86400

    func lookup(url: URL, policyHost: Bool = false) -> AssistantWebPageCacheEntry? {
        let key = normalized(url)
        guard let entry = entries[key] else { return nil }
        let ttl = policyHost ? policyTTL : genericTTL
        guard Date().timeIntervalSince(entry.fetchedAt) < ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    func store(url: URL, bodyText: String) {
        let key = normalized(url)
        let host = url.host?.lowercased() ?? ""
        entries[key] = AssistantWebPageCacheEntry(
            url: key,
            bodyText: String(bodyText.prefix(80_000)),
            fetchedAt: Date(),
            host: host
        )
        if entries.count > 1_500 {
            let sorted = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            for pair in sorted.prefix(entries.count - 1_400) {
                entries.removeValue(forKey: pair.key)
            }
        }
    }

    func evictAllForMemoryPressure() {
        entries.removeAll(keepingCapacity: false)
    }

    private func normalized(_ url: URL) -> String {
        url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
