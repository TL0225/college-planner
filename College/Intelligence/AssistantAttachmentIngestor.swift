import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

#if os(macOS)
import AppKit
#endif

/// On-device ingestion for AI Assistant attachments: PDF text, PDF render + OCR fallback, image copies for MLX vision.
enum AssistantAttachmentIngestor {

    struct Result: Sendable {
        /// Text block appended to planner / final prompts (bounded).
        let contextBlock: String
        /// Sandbox file URLs (e.g. PNG) suitable for `UserInput.Image.url` — bounded by the active context preset.
        let visionImageURLs: [URL]
        /// Short labels for transcript chips (filenames).
        let displayNames: [String]
    }

    private static var caps: AssistantContextBudget {
        AssistantContextBudget.currentFromUserDefaults()
    }

    /// Copies and normalizes imported URLs into temporary storage, builds prompt text and vision inputs.
    static func ingest(securityScopedURLs: [URL]) async -> Result {
        guard !securityScopedURLs.isEmpty else {
            return Result(contextBlock: "", visionImageURLs: [], displayNames: [])
        }

        cleanupExpiredSessionDirectories()

        let sessionDir: URL
        do {
            sessionDir = try makeUniqueSessionDirectory()
        } catch {
            return Result(
                contextBlock: "Attachment staging failed: \(error.localizedDescription)",
                visionImageURLs: [],
                displayNames: []
            )
        }

        var lines: [String] = []
        var visionURLs: [URL] = []
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
                await ingestPDF(
                    from: source,
                    sessionDir: sessionDir,
                    baseName: baseName,
                    lines: &lines,
                    visionURLs: &visionURLs
                )
            case "txt", "md", "markdown":
                ingestPlaintext(from: source, baseName: baseName, lines: &lines)
            case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff":
                if let copied = copyImageForVision(from: source, sessionDir: sessionDir, baseName: baseName) {
                    appendVisionURL(copied, visionURLs: &visionURLs)
                }
            default:
                lines.append("- \(baseName): unsupported type (.\(ext)); try PDF, image, or .txt.")
            }
        }

        let block = Self.joinContextLines(lines)
        return Result(contextBlock: block, visionImageURLs: visionURLs, displayNames: names)
    }

    // MARK: - Internals

    private static func appendVisionURL(_ url: URL, visionURLs: inout [URL]) {
        guard visionURLs.count < caps.maxVisionImages else { return }
        visionURLs.append(url)
    }

    private static func makeUniqueSessionDirectory() throws -> URL {
        let root = sessionAttachmentRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func sessionAttachmentRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("AssistantSessionAttachments", isDirectory: true)
    }

    private static func cleanupExpiredSessionDirectories(maxAge: TimeInterval = 24 * 60 * 60) {
        let root = sessionAttachmentRoot()
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for dir in dirs {
            let values = try? dir.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let date = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
            if date < cutoff {
                try? fm.removeItem(at: dir)
            }
        }
    }

    private static func ingestPDF(
        from url: URL,
        sessionDir: URL,
        baseName: String,
        lines: inout [String],
        visionURLs: inout [URL]
    ) async {
        do {
            let ingest = try SyllabusPDFIngestService().extractText(from: url)
            let clipped = String(ingest.cleanedText.prefix(caps.maxTextPerFile))
            lines.append("### \(baseName) (PDF, \(ingest.pageCount) pages)\n\(clipped)")
            return
        } catch SyllabusPDFIngestError.extractedEmptyText {
            lines.append("### \(baseName) (PDF)\nNative text extraction returned empty (likely scanned). OCR + rendered pages follow.")
            await renderAndOCRPDF(at: url, sessionDir: sessionDir, baseName: baseName, lines: &lines, visionURLs: &visionURLs)
        } catch {
            lines.append("### \(baseName) (PDF)\nCould not read PDF: \(error.localizedDescription)")
        }
    }

    private static func renderAndOCRPDF(
        at url: URL,
        sessionDir: URL,
        baseName: String,
        lines: inout [String],
        visionURLs: inout [URL]
    ) async {
        #if os(macOS)
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

            guard visionURLs.count < caps.maxVisionImages else { continue }
            let out = sessionDir.appendingPathComponent("\(baseName)-page-\(i + 1).png")
            if writePNG(cgImage: cgImage, to: out) {
                appendVisionURL(out, visionURLs: &visionURLs)
            }
        }

        let merged = ocrChunks.joined(separator: "\n\n")
        if !merged.isEmpty {
            lines.append(String(merged.prefix(caps.ocrMaxChars)))
        }
        #else
        lines.append("- \(baseName): scanned PDF vision path requires macOS.")
        #endif
    }

    #if os(macOS)
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

    private static func writePNG(cgImage: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, cgImage, nil)
        return CGImageDestinationFinalize(dest)
    }
    #endif

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

    private static func copyImageForVision(from url: URL, sessionDir: URL, baseName: String) -> URL? {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let dest = sessionDir.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
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
