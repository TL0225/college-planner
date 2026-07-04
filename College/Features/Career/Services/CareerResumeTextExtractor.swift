// CareerResumeTextExtractor.swift
// Feature: Career
// Purpose: PDFKit + Vision OCR text extraction for career resumes.

import AppKit
import Foundation
import PDFKit
import Vision

enum CareerResumeTextExtractor {
    struct ExtractionResult: Sendable {
        let plainText: String
        let pageCount: Int
        let usedOCR: Bool
    }

    static func extract(from fileURL: URL) async -> ExtractionResult {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return await extractPDF(fileURL: fileURL)
        case "txt", "md", "markdown", "rtf":
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            return ExtractionResult(plainText: text, pageCount: 1, usedOCR: false)
        default:
            if let text = (try? String(contentsOf: fileURL, encoding: .utf8)), !text.isEmpty {
                return ExtractionResult(plainText: text, pageCount: 1, usedOCR: false)
            }
            return ExtractionResult(plainText: "", pageCount: 0, usedOCR: false)
        }
    }

    private static func extractPDF(fileURL: URL) async -> ExtractionResult {
        await Task.detached(priority: .userInitiated) {
            let data: Data
            if let materialized = try? await VaultSourceFileMaterializer.materializedDataAsync(from: fileURL) {
                data = materialized
            } else {
                data = (try? Data(contentsOf: fileURL)) ?? Data()
            }
            guard !data.isEmpty else {
                return ExtractionResult(plainText: "", pageCount: 0, usedOCR: false)
            }

            guard let doc = PDFDocument(data: data) ?? PDFDocument(url: fileURL) else {
                return ExtractionResult(plainText: "", pageCount: 0, usedOCR: false)
            }

            let pageCount = doc.pageCount
            var parts: [String] = []
            for i in 0..<min(pageCount, 12) {
                if let page = doc.page(at: i), let s = page.string, !s.isEmpty {
                    parts.append(s)
                }
            }
            let joined = parts.joined(separator: "\n")
            if joined.count >= 80 {
                return ExtractionResult(plainText: joined, pageCount: pageCount, usedOCR: false)
            }
            let ocrText = ocrPDFPages(doc: doc, maxPages: min(pageCount, 6))
            return ExtractionResult(
                plainText: ocrText.isEmpty ? joined : ocrText,
                pageCount: pageCount,
                usedOCR: !ocrText.isEmpty
            )
        }.value
    }

    private static func ocrPDFPages(doc: PDFDocument, maxPages: Int) -> String {
        var out: [String] = []
        for i in 0..<maxPages {
            guard let page = doc.page(at: i) else { continue }
            let image = renderPageImage(page)
            let text = ocrNSImage(image)
            if !text.isEmpty { out.append(text) }
        }
        return out.joined(separator: "\n")
    }

    private static func renderPageImage(_ page: PDFPage, scale: CGFloat = 3) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        } else {
            return page.thumbnail(of: size, for: .mediaBox)
        }
        return image
    }

    private static func ocrNSImage(_ nsImage: NSImage) -> String {
        guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
