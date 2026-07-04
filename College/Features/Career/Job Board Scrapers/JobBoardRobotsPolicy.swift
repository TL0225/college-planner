// JobBoardRobotsPolicy.swift
// Feature: Career / Job Board Scrapers
// Purpose: robots.txt evaluation before hub-board fetches.

import Foundation

struct JobBoardRobotsRule: Sendable, Equatable {
    let pathPrefix: String
    let allowed: Bool
}

enum JobBoardRobotsPolicy {
    private struct CacheEntry: Sendable {
        let fetchedAt: Date
        let rules: [JobBoardRobotsRule]
        let crawlDelay: TimeInterval?
    }

    private actor CacheStore {
        static let shared = CacheStore()
        private var cache: [String: CacheEntry] = [:]

        func entry(forHost host: String, ttl: TimeInterval) -> CacheEntry? {
            guard let cached = cache[host], Date().timeIntervalSince(cached.fetchedAt) < ttl else { return nil }
            return cached
        }

        func store(_ entry: CacheEntry, host: String) {
            cache[host] = entry
        }

        func reset() {
            cache.removeAll()
        }
    }

    private static let cacheTTL: TimeInterval = 24 * 3600

    /// Returns nil when fetch is allowed; otherwise a user-facing reason.
    static func disallowedReason(for url: URL) async -> String? {
        guard let host = url.host?.lowercased() else { return "Invalid URL" }
        if host.contains("builtin.com"), !isAllowedBuiltInHubURL(url) {
            return "BuiltIn URL is blocked by robots policy (search/regional/apply paths)."
        }
        let rules = await rules(forHost: host)
        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query?.lowercased(), query.contains("action=get_jobs"), host.contains("remoteok") {
            return "RemoteOK AJAX endpoint is disallowed by robots.txt."
        }
        if queryContainsDisallowedBuiltInSearch(url) {
            return "BuiltIn search URLs are disallowed by robots.txt."
        }
        for rule in rules where path.hasPrefix(rule.pathPrefix) || rule.pathPrefix == "/" {
            if !rule.allowed { return "URL blocked by robots.txt (\(rule.pathPrefix))" }
        }
        return nil
    }

    static func canFetch(url: URL) async -> Bool {
        await disallowedReason(for: url) == nil
    }

    static func crawlDelay(forHost host: String) async -> TimeInterval? {
        await rulesEntry(forHost: host.lowercased())?.crawlDelay
    }

    static func isAllowedBuiltInHubURL(_ url: URL) -> Bool {
        guard url.host?.lowercased().contains("builtin.com") == true else { return false }
        let path = url.path.lowercased()
        if path.contains("/apply") { return false }
        if let query = url.query?.lowercased(), query.contains("search=") { return false }
        let regionalSuffixes = ["seattle", "san-francisco", "new-york", "boston", "austin", "chicago"]
        for suffix in regionalSuffixes where path.hasSuffix("/jobs/\(suffix)") || path.hasSuffix("/jobs/\(suffix)/") {
            return false
        }
        return path.hasPrefix("/jobs") || path.hasPrefix("/job/")
    }

    static func resetCacheForTesting() async {
        await CacheStore.shared.reset()
    }

    static func seedRobotsForTesting(host: String, body: String) async {
        await CacheStore.shared.store(
            CacheEntry(
                fetchedAt: Date(),
                rules: parseRules(from: body),
                crawlDelay: parseCrawlDelay(from: body)
            ),
            host: host.lowercased()
        )
    }

    private static func queryContainsDisallowedBuiltInSearch(_ url: URL) -> Bool {
        guard url.host?.lowercased().contains("builtin.com") == true else { return false }
        return url.query?.lowercased().contains("search=") == true
    }

    private static func rulesEntry(forHost host: String) async -> CacheEntry? {
        if let cached = await CacheStore.shared.entry(forHost: host, ttl: cacheTTL) {
            return cached
        }
        guard let robotsURL = URL(string: "https://\(host)/robots.txt") else { return nil }
        do {
            let (data, _) = try await JobBoardHTTP.get(url: robotsURL)
            let body = String(data: data, encoding: .utf8) ?? ""
            let entry = CacheEntry(
                fetchedAt: Date(),
                rules: parseRules(from: body),
                crawlDelay: parseCrawlDelay(from: body)
            )
            await CacheStore.shared.store(entry, host: host)
            return entry
        } catch {
            let fallback = CacheEntry(
                fetchedAt: Date(),
                rules: [JobBoardRobotsRule(pathPrefix: "/", allowed: true)],
                crawlDelay: nil
            )
            await CacheStore.shared.store(fallback, host: host)
            return fallback
        }
    }

    private static func rules(forHost host: String) async -> [JobBoardRobotsRule] {
        await rulesEntry(forHost: host)?.rules ?? [JobBoardRobotsRule(pathPrefix: "/", allowed: true)]
    }

    static func parseRules(from body: String) -> [JobBoardRobotsRule] {
        var rules: [JobBoardRobotsRule] = []
        var inStarAgent = false
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("user-agent:") {
                let agent = trimmed.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespaces).lowercased()
                inStarAgent = agent == "*"
                continue
            }
            guard inStarAgent else { continue }
            if lower.hasPrefix("disallow:") {
                let path = trimmed.dropFirst("disallow:".count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { rules.append(JobBoardRobotsRule(pathPrefix: path, allowed: false)) }
            } else if lower.hasPrefix("allow:") {
                let path = trimmed.dropFirst("allow:".count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { rules.append(JobBoardRobotsRule(pathPrefix: path, allowed: true)) }
            }
        }
        if rules.isEmpty { rules.append(JobBoardRobotsRule(pathPrefix: "/", allowed: true)) }
        return rules
    }

    static func parseCrawlDelay(from body: String) -> TimeInterval? {
        for line in body.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.hasPrefix("crawl-delay:") {
                let value = line.dropFirst("crawl-delay:".count).trimmingCharacters(in: .whitespaces)
                if let seconds = TimeInterval(value) { return seconds }
            }
        }
        return nil
    }
}
