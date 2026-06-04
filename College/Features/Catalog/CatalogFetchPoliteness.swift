// CatalogFetchPoliteness.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogFetchPoliteness.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// How aggressively to cap declared `robots.txt` crawl-delay before catalog HTTP GETs.
enum CatalogFetchPoliteness: Sendable {
    /// UI-thread-adjacent work: tight cap (legacy 3s behavior).
    case interactiveUserFacing
    /// Concurrent helpers: slightly looser cap (legacy 8s behavior).
    case interactiveBackground
    /// Bulk / background hydration: honor the parsed crawl-delay (up to throttle policy maximum).
    case bulk
    /// Light catalog index (1–2 pages per catoid): full robots crawl-delay, WebView allowed on real WAF pages.
    case catalogSkeleton
}
