// CatalogIngestSignature.swift
// Feature: Catalog
// Purpose: Versioned ingest signatures for skip/rescrape decisions.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

enum CatalogIngestSignature {
    static let v2Prefix = "v2:"

    /// Coarse program-count bucket so minor listing drift does not force full rescrape.
    static func programCountBucket(_ count: Int) -> String {
        switch count {
        case 0: return "0"
        case 1 ..< 50: return "1-49"
        case 50 ..< 200: return "50-199"
        case 200 ..< 500: return "200-499"
        default: return "500+"
        }
    }

    /// Legacy discovery signature from resolved catoid list (pre-scrape fast path).
    static func discoveryFromCatalogs(_ catalogs: [ModernCampusCatalogDescriptor]) -> String {
        let source = catalogs
            .map { "\($0.catoid)|\($0.title)" }
            .sorted()
            .joined(separator: "||")
        return digest(source)
    }

    /// v2: graph topology + dominant layout profile + program-count bucket.
    static func modernCampusV2(
        graphSourceSignature: String,
        layoutProfileID: String,
        programCount: Int
    ) -> String {
        let layout = layoutProfileID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let graph = graphSourceSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        let bucket = programCountBucket(programCount)
        let payload = [graph, layout.isEmpty ? "unknown" : layout, bucket].joined(separator: "::")
        return v2Prefix + digest(payload)
    }

    static func isV2(_ signature: String) -> Bool {
        signature.hasPrefix(v2Prefix)
    }

    private static func digest(_ source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
