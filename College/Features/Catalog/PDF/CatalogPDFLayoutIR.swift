// CatalogPDFLayoutIR.swift
// Feature: Catalog
// Purpose: Geometry-aware layout blocks with column detection and reading order.

import CoreGraphics
import Foundation

enum CatalogPDFLayoutBlockType: String, Sendable, Codable {
    case paragraph
    case heading
    case table
    case header
    case footer
    case sidebar
    case unknown
}

struct CatalogPDFLayoutBlock: Sendable, Hashable, Identifiable {
    let id: UUID
    let page: Int
    let boundingBox: CGRect?
    let text: String
    let blockType: CatalogPDFLayoutBlockType
    let readingOrder: Int
    let sourceLineIndices: [Int]

    init(
        id: UUID = UUID(),
        page: Int,
        boundingBox: CGRect?,
        text: String,
        blockType: CatalogPDFLayoutBlockType,
        readingOrder: Int,
        sourceLineIndices: [Int] = []
    ) {
        self.id = id
        self.page = page
        self.boundingBox = boundingBox
        self.text = text
        self.blockType = blockType
        self.readingOrder = readingOrder
        self.sourceLineIndices = sourceLineIndices
    }
}

enum CatalogPDFLayoutIRBuilder {
    private static let columnGapThreshold: CGFloat = 24

    static func build(from lines: [CatalogPDFLine]) -> [CatalogPDFLayoutBlock] {
        guard !lines.isEmpty else { return [] }

        var blocks: [CatalogPDFLayoutBlock] = []
        var current: [CatalogPDFLine] = []
        current.reserveCapacity(8)

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
            if current.count >= 24 {
                flush()
            }
        }
        flush()

        return assignReadingOrder(blocks)
    }

    /// Reorder lines within each page using x-coordinate column clustering.
    static func reorderLinesForReadingOrder(_ lines: [CatalogPDFLine]) -> [CatalogPDFLine] {
        let grouped = Dictionary(grouping: lines, by: \.pageIndex)
        var output: [CatalogPDFLine] = []
        output.reserveCapacity(lines.count)

        for page in grouped.keys.sorted() {
            let pageLines = grouped[page] ?? []
            output.append(contentsOf: reorderPageLines(pageLines))
        }
        return output
    }

    private static func reorderPageLines(_ lines: [CatalogPDFLine]) -> [CatalogPDFLine] {
        let withRects = lines.filter { $0.rect != nil }
        let withoutRects = lines.filter { $0.rect == nil }
        guard withRects.count >= 4 else {
            return lines.sorted {
                if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
                return $0.lineIndexOnPage < $1.lineIndexOnPage
            }
        }

        let xs = withRects.compactMap { $0.rect?.midX }.sorted()
        guard columnGapIsSignificant(xs), let splitX = columnSplitX(from: xs) else {
            return lines.sorted {
                if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
                return $0.lineIndexOnPage < $1.lineIndexOnPage
            }
        }

        let left = withRects
            .filter { ($0.rect?.midX ?? 0) <= splitX }
            .sorted { lhs, rhs in
                let dy = (lhs.rect?.minY ?? 0) - (rhs.rect?.minY ?? 0)
                if abs(dy) > 1 { return dy < 0 }
                return lhs.lineIndexOnPage < rhs.lineIndexOnPage
            }
        let right = withRects
            .filter { ($0.rect?.midX ?? 0) > splitX }
            .sorted { lhs, rhs in
                let dy = (lhs.rect?.minY ?? 0) - (rhs.rect?.minY ?? 0)
                if abs(dy) > 1 { return dy < 0 }
                return lhs.lineIndexOnPage < rhs.lineIndexOnPage
            }

        return left + right + withoutRects.sorted { $0.lineIndexOnPage < $1.lineIndexOnPage }
    }

    private static func columnGapIsSignificant(_ xs: [CGFloat]) -> Bool {
        guard xs.count >= 4 else { return false }
        var bestGap: CGFloat = 0
        for index in 0..<(xs.count - 1) {
            bestGap = max(bestGap, xs[index + 1] - xs[index])
        }
        return bestGap >= columnGapThreshold
    }

    private static func columnSplitX(from xs: [CGFloat]) -> CGFloat? {
        guard xs.count >= 4 else { return nil }
        var bestGap: CGFloat = 0
        var bestMid: CGFloat?
        for index in 0..<(xs.count - 1) {
            let gap = xs[index + 1] - xs[index]
            if gap > bestGap, gap >= columnGapThreshold {
                bestGap = gap
                bestMid = (xs[index] + xs[index + 1]) / 2
            }
        }
        return bestMid
    }

    private static func shouldStartNewBlock(before line: CatalogPDFLine, current: [CatalogPDFLine]) -> Bool {
        guard let prev = current.last else { return false }
        if line.pageIndex != prev.pageIndex { return true }
        if isLikelyHeading(line.text), !current.isEmpty { return true }
        if line.indentLevel < prev.indentLevel, current.count > 1 { return true }
        return false
    }

    private static func isLikelyHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        let letters = trimmed.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upperRatio = Double(letters.filter(\.isUppercase).count) / Double(letters.count)
        return upperRatio > 0.85 && trimmed.count < 60
    }

    private static func makeBlock(from lines: [CatalogPDFLine]) -> CatalogPDFLayoutBlock? {
        guard !lines.isEmpty else { return nil }
        let text = lines.map(\.text).joined(separator: "\n")
        let page = lines.first?.pageIndex ?? 0
        let rect = unionRect(lines.compactMap(\.rect))
        let blockType = classifyBlockType(text: text, lines: lines)
        return CatalogPDFLayoutBlock(
            page: page,
            boundingBox: rect,
            text: text,
            blockType: blockType,
            readingOrder: 0,
            sourceLineIndices: lines.map(\.lineIndexOnPage)
        )
    }

    private static func classifyBlockType(text: String, lines: [CatalogPDFLine]) -> CatalogPDFLayoutBlockType {
        let lower = text.lowercased()
        if lower.contains("table of contents") || lower.hasPrefix("page ") { return .header }
        if lower.contains("undergraduate bulletin") || lower.contains("graduate bulletin") { return .header }
        if isLikelyHeading(text) { return .heading }
        if looksLikeTable(text) { return .table }
        return .paragraph
    }

    private static func looksLikeTable(_ text: String) -> Bool {
        let rows = text.split(separator: "\n")
        guard rows.count >= 2 else { return false }
        let codedRows = rows.filter { $0.range(of: #"\b[A-Z]{2,8}\s+\d{3,4}\b"#, options: .regularExpression) != nil }
        return codedRows.count >= 2
    }

    private static func unionRect(_ rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func assignReadingOrder(_ blocks: [CatalogPDFLayoutBlock]) -> [CatalogPDFLayoutBlock] {
        let sorted = blocks.sorted { lhs, rhs in
            if lhs.page != rhs.page { return lhs.page < rhs.page }
            let ly = lhs.boundingBox?.minY ?? CGFloat(lhs.readingOrder)
            let ry = rhs.boundingBox?.minY ?? CGFloat(rhs.readingOrder)
            if abs(ly - ry) > 1 { return ly < ry }
            let lx = lhs.boundingBox?.minX ?? 0
            let rx = rhs.boundingBox?.minX ?? 0
            return lx < rx
        }
        return sorted.enumerated().map { index, block in
            CatalogPDFLayoutBlock(
                id: block.id,
                page: block.page,
                boundingBox: block.boundingBox,
                text: block.text,
                blockType: block.blockType,
                readingOrder: index,
                sourceLineIndices: block.sourceLineIndices
            )
        }
    }
}
