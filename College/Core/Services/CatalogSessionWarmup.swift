// CatalogSessionWarmup.swift
// Feature: Core
// Purpose: Core module — CatalogSessionWarmup.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Optional warm touch to the catalog origin (session cookies, CDN edge) before bulk hydration.
enum CatalogSessionWarmup {
    private static let defaultsKey = "catalog.sessionWarmupAt"
    private static let minInterval: TimeInterval = 6 * 3600

    static func prefetchIfNeeded(normalizedCatalogBase: String) async {
        let base = normalizedCatalogBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: defaultsKey)
        if last > 0, now - last < minInterval { return }

        let seedURL: String
        if let u = URL(string: base) {
            seedURL = u.appendingPathComponent("index.php").absoluteString
        } else {
            seedURL = base + (base.hasSuffix("/") ? "" : "/") + "index.php"
        }

        do {
            _ = try await ModernCampusEngine.fetchHTMLPublic(seedURL, politeness: .interactiveBackground)
            UserDefaults.standard.set(now, forKey: defaultsKey)
        } catch {
            DebugLogger.shared.log(
                "Catalog session warmup skipped: \(error.localizedDescription)",
                category: .system,
                level: .trace
            )
        }
    }
}
