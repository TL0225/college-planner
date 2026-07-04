// CatalogPDFPolicyExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFPolicyExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPDFPolicyExtractor {
    typealias PolicyRow = (
        sourceURL: String,
        navTitle: String,
        sectionHeading: String?,
        bodyText: String,
        catalogScope: String,
        contentHash: String,
        binding: String?
    )

    static func extractPolicyRows(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        sourceURL: String,
        navTitle: String = "Catalog Policies"
    ) -> [PolicyRow] {
        let policyText = classifiedBlocks
            .filter { $0.type == .policy && $0.confidence >= 0.5 }
            .sorted { $0.block.primaryPage < $1.block.primaryPage }
            .map(\.block.text)
            .joined(separator: "\n")

        return extractPolicyRows(fromText: policyText, headings: [], sourceURL: sourceURL, navTitle: navTitle)
    }

    /// Splits policy section text into one row per heading. When `headings` (e.g. from the PDF
    /// outline) are provided they anchor the split precisely; otherwise heading shape is inferred.
    static func extractPolicyRows(
        fromText text: String,
        headings: [String] = [],
        sourceURL: String,
        navTitle: String = "Catalog Policies"
    ) -> [PolicyRow] {
        let lines = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        let headingKeys = Set(headings.map(normalize).filter { !$0.isEmpty })

        var rows: [PolicyRow] = []
        var currentHeading: String?
        var body: [String] = []

        func flush() {
            let joined = body.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty || currentHeading != nil else { return }
            guard !joined.isEmpty else { body = []; return }
            rows.append(makeRow(
                sourceURL: sourceURL,
                navTitle: navTitle,
                sectionHeading: currentHeading,
                bodyText: joined
            ))
            body = []
        }

        for line in lines {
            if isHeading(line, headingKeys: headingKeys) {
                flush()
                currentHeading = line
            } else {
                body.append(line)
            }
        }
        flush()

        // If nothing split cleanly (no headings found), emit a single consolidated row.
        if rows.isEmpty {
            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else { return [] }
            return [makeRow(sourceURL: sourceURL, navTitle: navTitle, sectionHeading: nil, bodyText: joined)]
        }

        return rows
    }

    // MARK: - Helpers

    private static func makeRow(
        sourceURL: String,
        navTitle: String,
        sectionHeading: String?,
        bodyText: String
    ) -> PolicyRow {
        (
            sourceURL: sourceURL,
            navTitle: navTitle,
            sectionHeading: sectionHeading,
            bodyText: bodyText,
            catalogScope: scope(for: bodyText, heading: sectionHeading),
            contentHash: CatalogChunkProjection.contentHash(for: bodyText),
            binding: nil
        )
    }

    private static func scope(for body: String, heading: String?) -> String {
        let lower = (heading.map { $0 + " " } ?? "") + body.lowercased()
        if lower.contains("undergraduate") {
            return CatalogPolicyScope.undergraduate.rawValue
        }
        if lower.contains("graduate") || lower.contains("phd") || lower.contains("doctoral")
            || lower.contains("master") || lower.contains("jsmbs") || lower.contains("medical")
            || lower.contains("dental") {
            return CatalogPolicyScope.graduate.rawValue
        }
        return CatalogPolicyScope.shared.rawValue
    }

    private static func isHeading(_ line: String, headingKeys: Set<String>) -> Bool {
        if headingKeys.contains(normalize(line)) { return true }
        guard headingKeys.isEmpty else { return false } // when outline headings exist, trust them only

        // Inferred heading shape: short, title-case, no terminal punctuation, multiple words.
        guard line.count <= 70 else { return false }
        guard let first = line.first, first.isUppercase else { return false }
        if line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix(":") || line.hasSuffix(";") { return false }
        let words = line.split(separator: " ")
        guard (1...9).contains(words.count) else { return false }
        let capitalized = words.filter { $0.first?.isUppercase == true }.count
        return Double(capitalized) / Double(words.count) >= 0.6
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
