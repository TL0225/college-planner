// TransferProofValidator.swift
// Feature: Transfer / Proof
// Purpose: Transfer Database — validates a transcript/articulation proof PDF.
// Data: Reads a PDF via PDFKit; produces a deterministic validation result.

import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Validates that a submitted proof document looks like a genuine registrar transcript or an
/// official articulation printout. Heuristic + deterministic; never blocks on the network.
enum TransferProofValidator {
    private static let registrarKeywords = [
        "office of the registrar", "registrar", "official transcript",
        "transcript", "academic record", "statement of credit",
    ]
    private static let signatureKeywords = [
        "registrar signature", "signature", "/s/", "digitally signed",
        "authorized signature", "official seal",
    ]
    private static let acceptanceThreshold = 0.55

    static func validate(
        pdfAt url: URL,
        expectedUniversityName: String? = nil
    ) -> TransferProofValidationResult {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            return TransferProofValidationResult(
                isAcceptable: false,
                score: 0,
                textExtractionMethod: .none,
                notes: ["Document could not be opened as a PDF."]
            )
        }
        return validate(document: document, expectedUniversityName: expectedUniversityName)
        #else
        return TransferProofValidationResult(
            isAcceptable: false,
            score: 0,
            textExtractionMethod: .none,
            notes: ["PDFKit unavailable on this platform."]
        )
        #endif
    }

    #if canImport(PDFKit)
    static func validate(
        document: PDFDocument,
        expectedUniversityName: String? = nil
    ) -> TransferProofValidationResult {
        let rawText = document.string ?? ""
        let text = rawText.lowercased()
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let extractionMethod: TransferTextExtractionMethod = hasText ? .nativePDFText : .none

        var notes: [String] = []
        var score = 0.0

        // Registrar / transcript signals.
        let hasRegistrarHeader = registrarKeywords.contains { text.contains($0) }
        if hasRegistrarHeader {
            score += 0.4
        } else {
            notes.append("No registrar/transcript header text detected.")
        }

        // Signature / seal signals.
        let signatureDetected = signatureKeywords.contains { text.contains($0) }
        if signatureDetected { score += 0.2 }

        // University name detection.
        let detectedUniversityName = detectUniversityName(in: rawText)
        if let expected = expectedUniversityName?.lowercased(),
           !expected.isEmpty,
           text.contains(expected) {
            score += 0.25
        } else if detectedUniversityName != nil {
            score += 0.1
        } else {
            notes.append("Could not confirm an issuing university name.")
        }

        // Native (selectable) text is a strong authenticity signal versus a flat scan.
        if hasText { score += 0.1 } else {
            notes.append("No selectable text — document may be a photo/scan and needs OCR review.")
        }

        // PDF metadata.
        let attributes = document.documentAttributes ?? [:]
        let producer = attributes[PDFDocumentAttribute.producerAttribute] as? String
        let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        if producer?.isEmpty == false { score += 0.05 }

        let clampedScore = min(1.0, max(0.0, score))
        return TransferProofValidationResult(
            isAcceptable: clampedScore >= acceptanceThreshold && hasRegistrarHeader,
            score: clampedScore,
            detectedUniversityName: detectedUniversityName,
            hasRegistrarHeader: hasRegistrarHeader,
            signatureDetected: signatureDetected,
            pdfProducer: producer,
            pdfCreationDate: creationDate,
            textExtractionMethod: extractionMethod,
            notes: notes
        )
    }

    /// Looks for the first line containing "university" or "college" as a likely issuer name.
    private static func detectUniversityName(in rawText: String) -> String? {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines.prefix(25) {
            let lower = line.lowercased()
            if lower.contains("university") || lower.contains("college") || lower.contains("institute") {
                if line.count <= 80 { return line }
            }
        }
        return nil
    }
    #endif
}
