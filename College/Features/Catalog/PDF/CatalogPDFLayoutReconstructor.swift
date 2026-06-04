// CatalogPDFLayoutReconstructor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFLayoutReconstructor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 2: group raw lines into semantic text blocks (no regex entity extraction).
enum CatalogPDFLayoutReconstructor {
    private static let maxLinesPerBlock = 24
    private static let headingMaxLength = 80

    static func reconstruct(from lines: [CatalogPDFLine]) -> [CatalogPDFTextBlock] {
        guard !lines.isEmpty else { return [] }

        var blocks: [CatalogPDFTextBlock] = []
        var current: [CatalogPDFLine] = []
        current.reserveCapacity(12)

        func flush() {
            guard !current.isEmpty else { return }
            if let block = makeBlock(from: current) {
                blocks.append(block)
            }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if shouldStartNewBlock(before: line, current: current) {
                flush()
            }
            current.append(line)
            if current.count >= maxLinesPerBlock {
                flush()
            }
        }
        flush()
        return blocks
    }

    private static func shouldStartNewBlock(before line: CatalogPDFLine, current: [CatalogPDFLine]) -> Bool {
        guard !current.isEmpty else { return false }

        let prev = current.last!
        if line.pageIndex != prev.pageIndex {
            return true
        }

        if isLikelyHeading(line.text), !current.isEmpty {
            return true
        }

        if line.indentLevel < prev.indentLevel, current.count > 1 {
            return true
        }

        return false
    }

    private static func isLikelyHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= headingMaxLength else { return false }

        let letters = trimmed.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }

        let upperRatio = Double(letters.filter { $0.isUppercase }.count) / Double(letters.count)
        if upperRatio > 0.85, trimmed.count < 60 { return true }

        if trimmed.hasSuffix(":") && trimmed.count < 70 { return true }

        return false
    }

    private static func makeBlock(from lines: [CatalogPDFLine]) -> CatalogPDFTextBlock? {
        guard !lines.isEmpty else { return nil }
        let pages = lines.map(\.pageIndex)
        let range = (pages.min() ?? 0)...(pages.max() ?? 0)
        return CatalogPDFTextBlock(lines: lines, pageRange: range)
    }
}
