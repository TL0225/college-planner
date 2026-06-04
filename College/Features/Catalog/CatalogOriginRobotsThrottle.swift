// CatalogOriginRobotsThrottle.swift
// Feature: Catalog
// Purpose: Catalog module — CachedPolicy.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os

/// Per-origin politeness: fetch ``/robots.txt`` (cached), honor ``Crawl-delay`` for ``User-agent: *``.
///
/// - **Interactive** requests cap the *applied* delay so onboarding and taps stay responsive.
/// - **Bulk** hydration uses the full parsed delay (up to the cache maximum) to stay closer to ``robots.txt``.
enum CatalogOriginRobotsThrottle: Sendable {
    private struct CachedPolicy: Sendable {
        let fetchedAt: Date
        let crawlDelaySecondsDeclared: TimeInterval
        let disallowPrefixes: [String]
    }

    nonisolated(unsafe) private static var cache: [String: CachedPolicy] = [:]
    nonisolated(unsafe) private static var lock = OSAllocatedUnfairLock()

    private static let cacheTTL: TimeInterval = 6 * 60 * 60

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    /// Before an HTTP GET to a catalog origin, wait according to crawl-delay and serialized per-host spacing.
    static func applyPoliteDelayBeforeFetch(url: URL, politeness: CatalogFetchPoliteness) async {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }

        let policy = await loadPolicy(for: host)
        let declared = max(0, policy.crawlDelaySecondsDeclared)

        let minSpacing: TimeInterval
        switch politeness {
        case .interactiveUserFacing:
            minSpacing = min(declared, 3.0)
        case .interactiveBackground:
            minSpacing = min(declared, 8.0)
        case .bulk:
            minSpacing = declared
        case .catalogSkeleton:
            minSpacing = declared
        }

        await CatalogHostRequestScheduler.shared.acquire(host: host, minSpacing: minSpacing)
    }

    /// `true` when the URL path appears disallowed for `User-agent: *` (prefix match).
    static func hostMayDisallowPath(url: URL) async -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let policy = await loadPolicy(for: host)
        let path = url.path.lowercased()
        for prefix in policy.disallowPrefixes {
            let p = prefix.lowercased()
            if !p.isEmpty, path.hasPrefix(p) { return true }
        }
        return false
    }

    private static func loadPolicy(for host: String) async -> (crawlDelaySecondsDeclared: TimeInterval, disallowPrefixes: [String]) {
        let cached: CachedPolicy? = lock.withLock {
            if let existing = cache[host], Date().timeIntervalSince(existing.fetchedAt) < cacheTTL {
                return existing
            }
            return nil
        }
        if let cached {
            return (cached.crawlDelaySecondsDeclared, cached.disallowPrefixes)
        }

        var parsedDelay: TimeInterval = 0
        var disallows: [String] = ["/search_advanced.php", "/ajax/", "/portfolio.php", "/portfolio_nopop.php"]

        if let robotsURL = URL(string: "https://\(host)/robots.txt") {
            var req = URLRequest(url: robotsURL)
            req.timeoutInterval = 12
            req.setValue("CollegeApp/1.0 (macOS; robots)", forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await session.data(for: req),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let text = String(data: data, encoding: .utf8) {
                let parsed = parseRobotsForStarAgent(text)
                parsedDelay = parsed.crawlDelay
                disallows = mergeUnique(disallows, parsed.disallows)
            }
        }

        let entry = CachedPolicy(
            fetchedAt: Date(),
            crawlDelaySecondsDeclared: max(0, min(parsedDelay, 600)),
            disallowPrefixes: disallows
        )
        lock.withLock { cache[host] = entry }
        if parsedDelay > 0 {
            DebugLogger.shared.log(
                "🤖 robots.txt \(host): crawl-delay=\(Int(parsedDelay))s disallows=\(disallows.count)",
                category: .system
            )
        }
        return (entry.crawlDelaySecondsDeclared, entry.disallowPrefixes)
    }

    private static func mergeUnique(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set(a.map { $0.lowercased() })
        var out = a
        for s in b {
            let k = s.lowercased()
            if seen.insert(k).inserted { out.append(s) }
        }
        return out
    }

    private static func parseRobotsForStarAgent(_ text: String) -> (crawlDelay: TimeInterval, disallows: [String]) {
        var disallows: [String] = []
        var crawl: TimeInterval = 0
        var appliesToStar = false

        let lines = text.split(whereSeparator: \.isNewline)
        for raw in lines {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()
            if lower.hasPrefix("user-agent:") {
                let ua = trimmed.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                appliesToStar = ua == "*"
                continue
            }

            guard appliesToStar else { continue }

            if lower.hasPrefix("disallow:") {
                let path = trimmed.dropFirst("disallow:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty { disallows.append(path) }
            } else if lower.hasPrefix("crawl-delay:") {
                let rawNum = trimmed.dropFirst("crawl-delay:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Double(rawNum), v > crawl { crawl = v }
            }
        }

        return (crawl, disallows)
    }
}
