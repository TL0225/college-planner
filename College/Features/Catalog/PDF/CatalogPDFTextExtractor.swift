// CatalogPDFTextExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFTextExtractor.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation
import PDFKit
import Vision

/// Stage 1: raw geometry-ready lines from PDFKit (no entity guessing).
actor CatalogPDFTextExtractor {
    let pageCount: Int
    private let document: PDFDocument
    private var ocrPagesUsedCount: Int = 0

    init(pdfURL: URL) throws {
        guard let doc = PDFDocument(url: pdfURL) else {
            throw CatalogPDFError.failedToOpenPDF
        }
        self.document = doc
        self.pageCount = doc.pageCount
    }

    /// All lines in document order with indent heuristics.
    func extractRawLines(
        ocrFallback: Bool = false,
        onPageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [CatalogPDFLine] {
        var out: [CatalogPDFLine] = []
        out.reserveCapacity(pageCount * 40)

        for pageIndex in 0..<pageCount {
            if pageIndex == 0 || pageIndex % 25 == 0 || pageIndex == pageCount - 1 {
                onPageProgress?(pageIndex + 1, pageCount)
            }
            let pageLines = extractPageLineStrings(pageIndex: pageIndex, ocrFallback: ocrFallback)
            for (lineIndex, text) in pageLines.enumerated() {
                let indent = leadingWhitespaceCount(in: text)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                out.append(
                    CatalogPDFLine(
                        text: trimmed,
                        pageIndex: pageIndex,
                        lineIndexOnPage: lineIndex,
                        indentLevel: indent
                    )
                )
            }
        }
        return out
    }

    func extractPageText(pageIndex: Int) -> String {
        guard let page = document.page(at: pageIndex) else { return "" }
        return (page.string ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bounded page-range text for archive pass (legacy page blob API).
    func extractPagesText(
        pageRange: Range<Int>,
        ocrFallback: Bool = false
    ) -> ([Int: String], removedLineCount: Int) {
        guard pageRange.lowerBound >= 0, pageRange.upperBound <= pageCount else {
            return ([:], 0)
        }

        var perPageLines: [[String]] = []
        perPageLines.reserveCapacity(pageRange.count)

        for idx in pageRange {
            perPageLines.append(extractPageLineStrings(pageIndex: idx, ocrFallback: ocrFallback))
        }

        let (cleanedLinesPerPage, removedCount) = PDFPageTextCleaner.stripRepeatedHeadersAndFooters(perPageLines)
        var out: [Int: String] = [:]
        out.reserveCapacity(cleanedLinesPerPage.count)

        var cursor = 0
        for pageIndex in pageRange {
            let lines = cleanedLinesPerPage[safe: cursor] ?? perPageLines[safe: cursor] ?? []
            out[pageIndex] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cursor += 1
        }

        return (out, removedCount)
    }

    func ocrPagesUsed() -> Int { ocrPagesUsedCount }

    private func extractPageLineStrings(pageIndex: Int, ocrFallback: Bool) -> [String] {
        guard let page = document.page(at: pageIndex) else { return [] }

        var text = (page.string ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        if ocrFallback {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonWhitespaceCount = trimmed.filter { !$0.isWhitespace && !$0.isNewline }.count
            if nonWhitespaceCount < 40 {
                text = Self.ocrPDFPageTextSync(page: page)
                if !text.isEmpty {
                    ocrPagesUsedCount += 1
                }
            }
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func ocrPDFPageTextSync(page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
        let nsImage = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " || ch == "\t" { count += 1 } else { break }
        }
        return min(count / 2, 8)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
