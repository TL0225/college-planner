// ModernCampusSidebarParsing.swift
// Feature: Catalog
// Purpose: Shared Modern Campus / Acalog sidebar selector strategy used by the engine
//          and the catalog discoverer, so the (identical) selectors live in one place.
// Data: Pure HTML/DOM helpers (SwiftSoup); no persistence.

import Foundation
import SwiftSoup

/// Centralized sidebar anchor selection for Modern Campus (Acalog) catalog pages.
///
/// Acalog renders the left navigation as `table.block_n2_links` containing
/// `div.n2_links > a[href=…navoid=…]`. Older / variant layouts scatter the same links,
/// so callers fall back to a broad `navoid=`-scoped selector. Each call site still applies
/// its own URL resolution and filtering on top of the returned anchors.
enum ModernCampusSidebarParsing {
    static let containerSelector = "table.block_n2_links.link_table, table.block_n2_links.links_table"
    static let primaryAnchorSelector = "div.n2_links a[href]"
    static let fallbackAnchorSelector = "a[href*='content.php'][href*='navoid='], .block_n2_links a[href*='navoid='], td.block_n2_and_content a[href*='navoid='], a.navbar[href*='navoid=']"

    /// Returns sidebar anchor elements: prefers anchors inside the navigation container,
    /// falling back to the broad `navoid=`-scoped selector when the container is absent or empty.
    static func anchors(in doc: Document) -> [Element] {
        let container = (try? doc.select(containerSelector).first()) ?? doc
        let primary = (try? container.select(primaryAnchorSelector).array()) ?? []
        if !primary.isEmpty { return primary }
        return (try? doc.select(fallbackAnchorSelector).array()) ?? []
    }
}
