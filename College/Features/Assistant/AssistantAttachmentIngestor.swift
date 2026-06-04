// AssistantAttachmentIngestor.swift
// Feature: Assistant
// Purpose: Assistant module — Result.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

import AppKit

/// On-device ingestion for AI Assistant attachments: PDF text and OCR, image OCR, plain text.
enum AssistantAttachmentIngestor {

    struct Result: Sendable {
        /// Text block appended to planner / final prompts (bounded).
        let contextBlock: String
        /// Short labels for transcript chips (filenames).
        let displayNames: [String]
    }

    private static var caps: AssistantContextBudget {
        AssistantContextBudget.currentFromUserDefaults()
    }

    /// Copies and normalizes imported URLs into temporary storage and builds prompt text.
    static func ingest(securityScopedURLs: [URL]) async -> Result {
        guard !securityScopedURLs.isEmpty else {
            return Result(contextBlock: "", displayNames: [])
        }

        var lines: [String] = []
        var names: [String] = []

        for source in securityScopedURLs.prefix(8) {
            let baseName = source.lastPathComponent
            names.append(baseName)

            let accessing = source.startAccessingSecurityScopedResource()
            defer {
                if accessing { source.stopAccessingSecurityScopedResource() }
            }

            let ext = source.pathExtension.lowercased()
            switch ext {
            case "pdf":
                await ingestPDF(from: source, baseName: baseName, lines: &lines)
            case "txt", "md", "markdown":
                ingestPlaintext(from: source, baseName: baseName, lines: &lines)
            case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff":
                await ingestImage(from: source, baseName: baseName, lines: &lines)
            default:
                lines.append("- \(baseName): unsupported type (.\(ext)); try PDF, image, or .txt.")
            }
        }

        let block = Self.joinContextLines(lines)
        return Result(contextBlock: block, displayNames: names)
    }

    // MARK: - Internals

    private static func ingestPDF(from url: URL, baseName: String, lines: inout [String]) async {
        do {
            let ingest = try SyllabusPDFIngestService().extractText(from: url)
            let clipped = String(ingest.cleanedText.prefix(caps.maxTextPerFile))
            lines.append("### \(baseName) (PDF, \(ingest.pageCount) pages)\n\(clipped)")
            return
        } catch SyllabusPDFIngestError.extractedEmptyText {
            lines.append("### \(baseName) (PDF)\nNative text extraction returned empty (likely scanned). OCR follows.")
            await renderAndOCRPDF(at: url, baseName: baseName, lines: &lines)
        } catch {
            lines.append("### \(baseName) (PDF)\nCould not read PDF: \(error.localizedDescription)")
        }
    }

    private static func renderAndOCRPDF(
        at url: URL,
        baseName: String,
        lines: inout [String]
    ) async {
        guard let doc = PDFDocument(url: url) else {
            lines.append("- \(baseName): failed to open PDF for rendering.")
            return
        }
        let pageCount = doc.pageCount
        guard pageCount > 0 else { return }

        var ocrChunks: [String] = []
        let limit = min(caps.maxRenderedPDFPages, pageCount)
        for i in 0..<limit {
            guard let page = doc.page(at: i) else { continue }
            guard let cgImage = pageCGImage(page: page) else { continue }

            let ocr = (try? await recognizeText(cgImage: cgImage)) ?? ""
            if !ocr.isEmpty {
                ocrChunks.append("--- page \(i + 1) ---\n\(ocr)")
            }
        }

        let merged = ocrChunks.joined(separator: "\n\n")
        if !merged.isEmpty {
            lines.append(String(merged.prefix(caps.ocrMaxChars)))
        }
    }

    private static func ingestImage(from url: URL, baseName: String, lines: inout [String]) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            lines.append("### \(baseName)\nCould not read image.")
            return
        }
        let ocr = (try? await recognizeText(cgImage: cgImage)) ?? ""
        if ocr.isEmpty {
            lines.append("### \(baseName)\nNo text recognized in image.")
        } else {
            lines.append("### \(baseName) (image OCR)\n\(String(ocr.prefix(caps.maxTextPerFile)))")
        }
    }

    private static func pageCGImage(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let pixelWidth = max(1, Int(bounds.width * scale))
        let pixelHeight = max(1, Int(bounds.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        ctx.saveGState()
        NSColor.white.set()
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func recognizeText(cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = (request.results as [VNRecognizedTextObservation]?) ?? []
                    let strings = observations.flatMap { $0.topCandidates(1).map(\.string) }
                    cont.resume(returning: strings.joined(separator: "\n"))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func ingestPlaintext(from url: URL, baseName: String, lines: inout [String]) {
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let clipped = String(raw.prefix(caps.maxTextPerFile))
            lines.append("### \(baseName)\n\(clipped)")
        } catch {
            lines.append("### \(baseName)\nCould not read text: \(error.localizedDescription)")
        }
    }

    private static func joinContextLines(_ parts: [String]) -> String {
        var merged = parts.joined(separator: "\n\n")
        if merged.count > caps.maxTotalContext {
            merged = String(merged.prefix(caps.maxTotalContext)) + "\n…(truncated)"
        }
        if merged.isEmpty { return "" }
        return "User-provided attachments (local, on-device):\n\n" + merged
    }
}
