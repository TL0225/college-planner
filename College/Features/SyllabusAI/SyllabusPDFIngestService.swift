// SyllabusPDFIngestService.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — SyllabusIngestResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import PDFKit

enum SyllabusPDFIngestError: LocalizedError {
    case fileNotFound
    case failedToOpenPDF
    case extractedEmptyText

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Syllabus PDF could not be found."
        case .failedToOpenPDF:
            return "Could not open the syllabus PDF."
        case .extractedEmptyText:
            return "Could not extract any text from this PDF. Make sure it's a native (non-scanned) PDF."
        }
    }
}

struct SyllabusIngestResult: Sendable {
    let rawText: String
    let cleanedText: String
    let pageCount: Int
    let removedLineCount: Int
}

/// User-uploaded syllabus PDF text extraction (Gemma analysis path). Catalog bulletins use `College/Catalog/PDF/`.
struct SyllabusPDFIngestService {
    func extractText(from pdfURL: URL) throws -> SyllabusIngestResult {
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw SyllabusPDFIngestError.fileNotFound
        }

        guard let doc = PDFDocument(url: pdfURL) else {
            throw SyllabusPDFIngestError.failedToOpenPDF
        }

        let pageCount = doc.pageCount
        var perPageLines: [[String]] = []
        perPageLines.reserveCapacity(pageCount)

        var rawParts: [String] = []
        rawParts.reserveCapacity(pageCount)

        for idx in 0..<pageCount {
            guard let page = doc.page(at: idx) else {
                perPageLines.append([])
                continue
            }

            let text = (page.string ?? "")
            rawParts.append(text)

            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            perPageLines.append(lines)
        }

        let rawText = rawParts
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if rawText.isEmpty {
            throw SyllabusPDFIngestError.extractedEmptyText
        }

        let (cleanedLinesPerPage, removedCount) = PDFPageTextCleaner.stripRepeatedHeadersAndFooters(perPageLines)
        let cleanedText = cleanedLinesPerPage
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SyllabusIngestResult(
            rawText: rawText,
            cleanedText: cleanedText.isEmpty ? rawText : cleanedText,
            pageCount: pageCount,
            removedLineCount: removedCount
        )
    }
}
