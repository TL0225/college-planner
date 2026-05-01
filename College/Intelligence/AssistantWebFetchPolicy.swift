import Foundation

/// Host allowlist for assistant-driven page fetches (SearXNG result hosts + user-configured extras).
enum AssistantWebFetchPolicy: Sendable {
    private static let policyHostsKey = "assistant.web.policyHosts"

    static func registerRecentSearchHosts(from urls: [String]) {
        let hosts = urls.compactMap { URL(string: $0)?.host?.lowercased() }
        guard !hosts.isEmpty else { return }
        var recent = Self.loadRecentHosts()
        let now = Date().timeIntervalSince1970
        for h in hosts {
            recent[h] = now
        }
        Self.pruneRecentHosts(&recent, max: 40, ttlSeconds: 3600)
        Self.saveRecentHosts(recent)
    }

    static func isHostAllowedForFetch(_ host: String) -> Bool {
        let h = host.lowercased()
        if AssistantWebSearchSettings.extraFetchHosts.contains(h) { return true }
        if loadPolicyHosts().contains(h) {
            return true
        }
        let recent = Self.loadRecentHosts()
        guard let ts = recent[h] else { return false }
        return Date().timeIntervalSince1970 - ts < 3600
    }

    static func isURLAllowedForFetch(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return isHostAllowedForFetch(host)
    }

    private static let recentKey = "assistant.web.recentSearchHosts"

    private static func loadRecentHosts() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: recentKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return decoded
    }

    static func registerPolicyHosts(_ hosts: Set<String>) {
        let normalized = Array(hosts.map { $0.lowercased() }).sorted()
        UserDefaults.standard.set(normalized, forKey: policyHostsKey)
    }

    private static func loadPolicyHosts() -> Set<String> {
        let hosts = UserDefaults.standard.array(forKey: policyHostsKey) as? [String] ?? []
        return Set(hosts.map { $0.lowercased() })
    }

    private static func saveRecentHosts(_ map: [String: TimeInterval]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }

    private static func pruneRecentHosts(_ map: inout [String: TimeInterval], max: Int, ttlSeconds: TimeInterval) {
        let now = Date().timeIntervalSince1970
        map = map.filter { now - $0.value < ttlSeconds }
        if map.count <= max { return }
        let sorted = map.sorted { $0.value < $1.value }
        let drop = map.count - max
        for pair in sorted.prefix(drop) {
            map.removeValue(forKey: pair.key)
        }
    }
}
