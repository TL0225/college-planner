// ResumePDFTestFixtures.swift
// Feature: Shared
// Purpose: Generate minimal text-based PDF fixtures for resume/vault tests.

import AppKit
import CoreText
import Foundation

enum ResumePDFTestFixtures {
    /// Plain text long enough for CareerResumeTextExtractor and parser compliance gates.
    static let samplePlainText: String = String(
        repeating: """
        Timothy Leung — Software Engineer
        Experience: Built APIs with Swift, Workday integrations, vault document pipelines, and ATS scoring.
        Skills: Swift, SwiftUI, SwiftData, PDFKit, XCTest, CI release gates, UAT oversight, catalog ingest.
        Education: Computer Science — distributed systems, performance profiling, Instruments baselines.

        """,
        count: 6
    )

    /// Writes a single-page text PDF suitable for PDFKit text extraction (no OCR).
    static func writeSampleResumePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw NSError(
                domain: "ResumePDFTestFixtures",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"]
            )
        }

        context.beginPDFPage(nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        let attributed = NSAttributedString(string: samplePlainText, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 54, y: 54, width: 504, height: 684), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
    }

    /// Temp file with a valid `%PDF` header and extractable body text.
    static func materializeSamplePDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-fixture-\(UUID().uuidString).pdf")
        try writeSampleResumePDF(to: url)
        return url
    }
}
