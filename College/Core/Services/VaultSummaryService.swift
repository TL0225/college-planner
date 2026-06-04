// VaultSummaryService.swift
// Feature: Core
// Purpose: Core module — VaultSummaryService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import PDFKit
import SwiftData

// MARK: - VaultSummaryService

@MainActor final class VaultSummaryService {

    static let shared = VaultSummaryService()

    private init() {}

    func summarize(doc: VaultDocument) async -> String? {
        guard let decryptedURL = CollegePersistence.shared.decryptedTempURLForStoredRelativePath(
            doc.localRelativePath,
            displayFileName: doc.fileName
        ) else {
            return nil
        }
        return await summarizePDF(at: decryptedURL, persist: { summary in
            VaultDocumentMetadataAccess.updateSummary(id: doc.id, summary: summary)
        })
    }

    func summarizeIfNeeded(doc: VaultDocument) async {
        guard doc.summaryText == nil else { return }
        guard doc.fileName.lowercased().hasSuffix(".pdf") else { return }
        _ = await summarize(doc: doc)
    }

    private func summarizePDF(at decryptedURL: URL, persist: (String) -> Void) async -> String? {
        guard let pdfDocument = PDFDocument(url: decryptedURL),
              let rawText = pdfDocument.string,
              !rawText.isEmpty else {
            return nil
        }
        let truncatedText = String(rawText.prefix(1500))
        let prompt = "Summarize this academic document in 3-5 bullet points. Be concise. Document: \(truncatedText)"

        let rawSummary: String
        do {
            guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker) else {
                return nil
            }
            rawSummary = try await LocalLLMRunner.shared.generateJSON(
                prompt: "/no_think\n" + prompt,
                modelPath: modelPath,
                maxTokens: 300
            )
        } catch {
            print("[VaultSummaryService] LLM generation failed: \(error)")
            return nil
        }

        let cleaned = rawSummary
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        persist(cleaned)
        return cleaned
    }
}
