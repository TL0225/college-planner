// CatalogPDFEngine.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFEngine.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import PDFKit

/// Catalog bulletin parsing — hierarchical document model, not Syllabus AI.
actor CatalogPDFEngine {
    func buildFoundation(from pdfURL: URL) throws -> CatalogPDFFoundationResult {
        guard let doc = PDFDocument(url: pdfURL) else {
            throw CatalogPDFError.failedToOpenPDF
        }
        let pageCount = doc.pageCount
        let sections = CatalogPDFSectionClassifier.classify(input: .init(document: doc))
        return CatalogPDFFoundationResult(pageCount: pageCount, sections: sections)
    }

    func buildHealthReport(from pdfURL: URL) throws -> CatalogPDFHealthReport {
        guard let doc = PDFDocument(url: pdfURL) else {
            throw CatalogPDFError.failedToOpenPDF
        }
        let pageCount = doc.pageCount
        let outlineEntryCount = Self.countOutlineEntries(root: doc.outlineRoot)
        var lowTextDensityPages = 0
        for idx in 0..<pageCount {
            guard let page = doc.page(at: idx) else { continue }
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
}
