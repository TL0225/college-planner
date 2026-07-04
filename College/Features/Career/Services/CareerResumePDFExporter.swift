// CareerResumePDFExporter.swift
// Feature: Career
// Purpose: Export ATS-safe single-column PDF from resume vault document.

import AppKit
import CoreText
import Foundation
import PDFKit

enum CareerResumePDFExporter {
    @MainActor
    static func exportATSSafePDF(
        sourceDocumentID: UUID,
        collegePersistence: CollegePersistence = .shared
    ) async throws -> VaultDocument? {
        guard let source = try collegePersistence.vaultRepository.fetchDocument(id: sourceDocumentID) else {
            return nil
        }
        guard let temp = await collegePersistence.vaultRepository.decryptedTempURLForStoredRelativePath(
            source.localRelativePath,
            displayFileName: source.fileName
        ) else { return nil }
        defer {
            if collegePersistence.urlForVaultDocument(source) != temp {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        let extracted = await CareerResumeTextExtractor.extract(from: temp)
        let plain = extracted.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }

        let structured = await structureWithLLM(plain) ?? plain
        let pdfData = renderSingleColumnPDF(text: structured)
        let exportName = (source.customDisplayName ?? source.fileName)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            + "_ATS.pdf"

        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(exportName)
        try pdfData.write(to: exportURL)

        let parentID = try collegePersistence.careerRepository.ensureCareerResumesVaultFolder(
            vaultRepository: collegePersistence.vaultRepository
        )
        try await collegePersistence.vaultRepository.addVaultDocument(
            fromSelectedURL: exportURL,
            category: VaultRepository.VaultDocumentCategory.careerResume,
            source: "career_ats_export",
            parentFolderID: parentID
        )

        guard let exported = try collegePersistence.vaultRepository.fetchDocuments(
            category: VaultRepository.VaultDocumentCategory.careerResume.rawValue,
            limit: 1
        ).first else { return nil }

        exported.versionOf = source.id
        collegePersistence.save()
        collegePersistence.bumpVaultRevision()
        return exported
    }

    private static func structureWithLLM(_ plain: String) async -> String? {
        let prompt = """
        Reformat this resume as plain text with clear single-column sections:
        CONTACT, SUMMARY, EXPERIENCE, EDUCATION, SKILLS.
        Return strict JSON: { "text": String }
        Resume:
        \(plain.prefix(12_000))
        """
        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return nil }
        struct Response: Codable { var text: String? }
        return try? JSONDecoder().decode(Response.self, from: data).text
    }

    static func renderSingleColumnPDF(text: String) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let textWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        let font = NSFont.systemFont(ofSize: 11)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentRange = CFRange(location: 0, length: 0)
        let fullLength = CFAttributedStringGetLength(attributed)

        while currentRange.location < fullLength {
            context.beginPDFPage(nil)
            let framePath = CGPath(
                rect: CGRect(x: margin, y: margin, width: textWidth, height: pageHeight - margin * 2),
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: currentRange.location, length: 0),
                framePath,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visible.length
            context.endPDFPage()
            if visible.length == 0 { break }
        }

        context.closePDF()
        return pdfData as Data
    }
}
