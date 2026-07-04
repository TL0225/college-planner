// CatalogPDFContext.swift
// Feature: Catalog
// Purpose: Shared document context for catalog PDF ingest.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation
import PDFKit
import Vision

/// Owns a single opened PDF document for one ingest run.
///
/// `PDFDocument` is not `Sendable`, so sharing it across separate actors/tasks trips
/// Swift concurrency checks. Keeping all PDFKit access inside this actor gives the
/// pipeline one document context without unsafe cross-actor document passing.
actor CatalogPDFContext {
    private struct LineVisualMeta {
        let fontSize: CGFloat?
        let isBold: Bool
    }
    let pdfURL: URL
    let pageCount: Int
    private let document: PDFDocument
    private let maxOCRPages: Int
    private var ocrPagesUsedCount: Int = 0

    init(
        pdfURL: URL,
        maxOCRPages: Int = CatalogPDFOperationalLimits.maxOCRPages
    ) throws {
        try CatalogPDFOperationalLimits.validateCachedFileSize(at: pdfURL)
        guard let document = PDFDocument(url: pdfURL) else {
            throw CatalogPDFError.failedToOpenPDF
        }
        try CatalogPDFOperationalLimits.validatePageCount(document.pageCount)

        self.pdfURL = pdfURL
        self.document = document
        self.pageCount = document.pageCount
        self.maxOCRPages = maxOCRPages
    }

    func buildFoundation() -> CatalogPDFFoundationResult {
        let sections = CatalogPDFSectionClassifier.classify(input: .init(document: document))
        return CatalogPDFFoundationResult(pageCount: pageCount, sections: sections)
    }

    func buildHealthReport() -> CatalogPDFHealthReport {
        let outlineEntryCount = Self.countOutlineEntries(root: document.outlineRoot)
        var lowTextDensityPages = 0

        for idx in 0..<pageCount {
            if Task.isCancelled { break }
            guard let page = document.page(at: idx) else { continue }
            let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let density = text.filter { !$0.isWhitespace && !$0.isNewline }.count
            if density < 40 {
                lowTextDensityPages += 1
            }
        }

        let layoutNote: String? = {
            if pageCount > 0, Double(lowTextDensityPages) / Double(pageCount) > 0.35 {
                return "PDFKit line reconstruction may be unreliable on many pages; v1 assumes newline boundaries roughly match layout."
            }
            return "v1 uses PDFKit page.string newlines; geometry fields reserved for v1.1."
        }()

        return CatalogPDFHealthReport(
            pageCount: pageCount,
            outlineEntryCount: outlineEntryCount,
            lowTextDensityPages: lowTextDensityPages,
            estimatedOCRPages: lowTextDensityPages,
            layoutNote: layoutNote
        )
    }

    func extractRawLines(
        ocrFallback: Bool = false,
        onPageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [CatalogPDFLine] {
        var out: [CatalogPDFLine] = []
        out.reserveCapacity(pageCount * 40)
        var perPageLines: [[String]] = []
        perPageLines.reserveCapacity(pageCount)

        for pageIndex in 0..<pageCount {
            if Task.isCancelled { break }
            if pageIndex == 0 || pageIndex % 25 == 0 || pageIndex == pageCount - 1 {
                onPageProgress?(pageIndex + 1, pageCount)
            }
            perPageLines.append(extractPageLineStrings(pageIndex: pageIndex, ocrFallback: ocrFallback))
        }

        let (cleanedLinesPerPage, _) = PDFPageTextCleaner.stripRepeatedHeadersAndFooters(perPageLines)
        for (pageIndex, pageLines) in cleanedLinesPerPage.enumerated() {
            let visualMeta = visualMetadataForPageLines(pageIndex: pageIndex, lines: pageLines)
            for (lineIndex, rawLine) in pageLines.enumerated() {
                let indent = Self.leadingWhitespaceCount(in: rawLine)
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let lineMeta = visualMeta[safe: lineIndex] ?? nil
                out.append(
                    CatalogPDFLine(
                        text: trimmed,
                        pageIndex: pageIndex,
                        lineIndexOnPage: lineIndex,
                        indentLevel: indent,
                        rect: nil,
                        fontSize: lineMeta?.fontSize,
                        isBold: lineMeta?.isBold ?? false
                    )
                )
            }
        }
        return out
    }

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
            if Task.isCancelled { break }
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

    func outlineEntries() -> [CatalogPDFOutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [CatalogPDFOutlineEntry] = []

        func visit(_ node: PDFOutline, depth: Int) {
            for idx in 0..<node.numberOfChildren {
                guard let child = node.child(at: idx) else { continue }
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    let pageIndex = child.destination?.page.map { document.index(for: $0) }
                    entries.append(CatalogPDFOutlineEntry(title: title, pageIndex: pageIndex, depth: depth))
                }
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return entries
    }

    private func extractPageLineStrings(pageIndex: Int, ocrFallback: Bool) -> [String] {
        guard let page = document.page(at: pageIndex) else { return [] }

        var text = (page.string ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        if ocrFallback, ocrPagesUsedCount < maxOCRPages {
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
            .filter { line in
                !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private static func countOutlineEntries(root: PDFOutline?) -> Int {
        guard let root else { return 0 }
        var count = 0
        func visit(_ node: PDFOutline) {
            count += 1
            for idx in 0..<node.numberOfChildren {
                if let child = node.child(at: idx) {
                    visit(child)
                }
            }
        }
        visit(root)
        return max(0, count - 1)
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

    private static func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " || ch == "\t" { count += 1 } else { break }
        }
        return min(count / 2, 8)
    }

    private func visualMetadataForPageLines(pageIndex: Int, lines: [String]) -> [LineVisualMeta?] {
        guard let page = document.page(at: pageIndex) else { return Array(repeating: nil, count: lines.count) }
        guard let attributed = page.attributedString, attributed.length > 0 else {
            return Array(repeating: nil, count: lines.count)
        }

        let fullText = attributed.string.replacingOccurrences(of: "\u{00A0}", with: " ")
        let nsText = fullText as NSString
        let rawAttributedLines = fullText.components(separatedBy: .newlines)
        var searchLocation = 0
        var buckets: [String: [LineVisualMeta]] = [:]

        for attributedLine in rawAttributedLines {
            let trimmed = attributedLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lineRange = nsText.range(of: attributedLine, options: [], range: NSRange(location: searchLocation, length: max(0, nsText.length - searchLocation)))
            guard lineRange.location != NSNotFound else { continue }
            searchLocation = lineRange.location + lineRange.length
            let font = attributed.attribute(NSAttributedString.Key.font, at: lineRange.location, effectiveRange: nil) as? NSFont
            let meta = LineVisualMeta(
                fontSize: font?.pointSize,
                isBold: font?.fontDescriptor.symbolicTraits.contains(NSFontDescriptor.SymbolicTraits.bold) ?? false
            )
            buckets[normalizeLine(trimmed), default: []].append(meta)
        }

        var resolved: [LineVisualMeta?] = []
        resolved.reserveCapacity(lines.count)
        for line in lines {
            let key = normalizeLine(line)
            if var options = buckets[key], !options.isEmpty {
                let picked = options.removeFirst()
                buckets[key] = options
                resolved.append(picked)
            } else {
                resolved.append(nil)
            }
        }
        return resolved
    }

    private func normalizeLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
