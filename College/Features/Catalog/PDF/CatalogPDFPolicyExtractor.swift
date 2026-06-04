// CatalogPDFPolicyExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFPolicyExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPDFPolicyExtractor {
    static func extractPolicyRows(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        sourceURL: String,
        navTitle: String = "Catalog Policies"
    ) -> [(sourceURL: String, navTitle: String, sectionHeading: String?, bodyText: String, catalogScope: String, contentHash: String, binding: String?)] {
        let policyText = classifiedBlocks
            .filter { $0.type == .policy && $0.confidence >= 0.5 }
            .map(\.block.text)
            .joined(separator: "\n\n")

        return extractPolicyRows(fromText: policyText, sourceURL: sourceURL, navTitle: navTitle)
    }

    static func extractPolicyRows(
        fromText text: String,
        sourceURL: String,
        navTitle: String = "Catalog Policies"
    ) -> [(sourceURL: String, navTitle: String, sectionHeading: String?, bodyText: String, catalogScope: String, contentHash: String, binding: String?)] {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [] }

        let scope: String
        let lower = cleaned.lowercased()
        if lower.contains("undergraduate") {
            scope = CatalogPolicyScope.undergraduate.rawValue
        } else if lower.contains("graduate")
                    || lower.contains("phd")
                    || lower.contains("doctoral")
                    || lower.contains("master")
                    || lower.contains("jsmbs")
                    || lower.contains("medical")
                    || lower.contains("dental") {
            scope = CatalogPolicyScope.graduate.rawValue
        } else {
            scope = CatalogPolicyScope.shared.rawValue
        }

        let hash = CatalogChunkProjection.contentHash(for: cleaned)

        return [
            (
                sourceURL: sourceURL,
                navTitle: navTitle,
                sectionHeading: nil,
                bodyText: cleaned,
                catalogScope: scope,
                contentHash: hash,
                binding: nil
            )
        ]
    }
}
