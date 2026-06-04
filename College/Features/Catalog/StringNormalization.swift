// StringNormalization.swift
// Feature: Catalog
// Purpose: Catalog module — StringNormalization.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension String {
    /// Normalizes common catalog text issues (NBSP, stray newlines/tabs, multiple spaces).
    ///
    /// The `\s+` regex is compiled once at app launch and reused on every call.
    /// This avoids the ~1–5 µs per-call overhead of Foundation's dynamic regex compilation
    /// which adds up to seconds of wasted CPU when called thousands of times during a catalog scrape.
    nonisolated func normalizedCatalogText() -> String {
        let withoutNBSP = replacingOccurrences(of: "\u{00A0}", with: " ")
        let range = NSRange(withoutNBSP.startIndex..., in: withoutNBSP)
        let collapsed = String._whitespaceCollapseRegex.stringByReplacingMatches(
            in: withoutNBSP,
            range: range,
            withTemplate: " "
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Compiled once; shared across all callers on any thread (NSRegularExpression is thread-safe).
    private static let _whitespaceCollapseRegex: NSRegularExpression = {
        // Force-try: pattern is a compile-time constant and will never fail.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: "\\s+")
    }()
}
