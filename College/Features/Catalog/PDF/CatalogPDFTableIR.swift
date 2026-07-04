// CatalogPDFTableIR.swift
// Feature: Catalog
// Purpose: Reconstruct tabular grids from layout blocks for requirement/course extraction.

import Foundation

struct CatalogPDFTableCell: Sendable, Hashable {
    let row: Int
    let column: Int
    let text: String
}

struct CatalogPDFTableIR: Sendable, Hashable, Identifiable {
    let id: UUID
    let page: Int
    let rows: [[String]]
    let cells: [CatalogPDFTableCell]
    let sourceBlockID: UUID?

    init(
        id: UUID = UUID(),
        page: Int,
        rows: [[String]],
        cells: [CatalogPDFTableCell] = [],
        sourceBlockID: UUID? = nil
    ) {
        self.id = id
        self.page = page
        self.rows = rows
        self.cells = cells
        self.sourceBlockID = sourceBlockID
    }

    var flattenedLines: [String] {
        rows.map { $0.joined(separator: " | ") }
    }
}

enum CatalogPDFTableIRBuilder {
    static func build(from blocks: [CatalogPDFLayoutBlock]) -> [CatalogPDFTableIR] {
        blocks
            .filter { $0.blockType == .table || looksTabular($0.text) }
            .compactMap(parseTable)
    }

    static func build(from textBlocks: [CatalogPDFTextBlock]) -> [CatalogPDFTableIR] {
        let layoutBlocks = textBlocks.map { block in
            CatalogPDFLayoutBlock(
                page: block.primaryPage,
                boundingBox: nil,
                text: block.text,
                blockType: looksTabular(block.text) ? .table : .paragraph,
                readingOrder: 0
            )
        }
        return build(from: layoutBlocks)
    }

    private static func looksTabular(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return false }
        let pipeRows = lines.filter { $0.contains("|") || $0.contains("\t") }.count
        let codeRows = lines.filter {
            $0.range(of: #"\b[A-Z]{2,8}\s+\d{3,4}\b"#, options: .regularExpression) != nil
        }.count
        return pipeRows >= 2 || codeRows >= 2
    }

    private static func parseTable(_ block: CatalogPDFLayoutBlock) -> CatalogPDFTableIR? {
        let rawLines = block.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard rawLines.count >= 2 else { return nil }

        var rows: [[String]] = []
        var cells: [CatalogPDFTableCell] = []
        for (rowIndex, line) in rawLines.enumerated() {
            let columns: [String]
            if line.contains("|") {
                columns = line.split(separator: "|").map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            } else if line.contains("\t") {
                columns = line.split(separator: "\t").map { String($0) }
            } else if let match = line.range(of: #"\b[A-Z]{2,8}\s+\d{3,4}\b.*"#, options: .regularExpression) {
                let code = String(line[match.lowerBound..<match.upperBound].prefix(while: { $0 != " " && $0 != "\t" }))
                let rest = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                columns = [code, rest].filter { !$0.isEmpty }
            } else {
                columns = [line]
            }
            rows.append(columns)
            for (columnIndex, value) in columns.enumerated() {
                cells.append(CatalogPDFTableCell(row: rowIndex, column: columnIndex, text: value))
            }
        }

        guard rows.count >= 2 else { return nil }
        return CatalogPDFTableIR(page: block.page, rows: rows, cells: cells, sourceBlockID: block.id)
    }
}
