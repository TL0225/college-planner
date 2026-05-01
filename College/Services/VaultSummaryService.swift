import Foundation
import PDFKit

// MARK: - VaultSummaryService

@MainActor final class VaultSummaryService {

    static let shared = VaultSummaryService()

    // MARK: - Init

    private init() {}

    // MARK: - Public Methods

    func summarize(doc: VaultDocumentEntity) async -> String? {
        // Step 1: Get the decrypted URL
        guard let decryptedURL = await CoreDataManager.shared.decryptedTempURLForVaultDocument(doc) else {
            return nil
        }

        // Step 2: Extract text from PDF (first 1500 chars)
        guard let pdfDocument = PDFDocument(url: decryptedURL),
              let rawText = pdfDocument.string,
              !rawText.isEmpty else {
            return nil
        }
        let truncatedText = String(rawText.prefix(1500))

        // Step 3: Build prompt
        let prompt = "Summarize this academic document in 3-5 bullet points. Be concise. Document: \(truncatedText)"

        // Step 4: Run LLM
        let rawSummary: String
        do {
            guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .gemma4) else {
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

        // Step 5: Clean up markdown asterisks
        let cleaned = rawSummary
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 6: Persist summary
        saveSummary(cleaned, to: doc)

        return cleaned
    }

    func summarizeIfNeeded(doc: VaultDocumentEntity) async {
        guard doc.summaryText == nil else { return }
        guard let fileName = doc.fileName,
              fileName.lowercased().hasSuffix(".pdf") else { return }
        _ = await summarize(doc: doc)
    }

    // MARK: - Private Helpers

    private func saveSummary(_ summary: String, to doc: VaultDocumentEntity) {
        let context = CoreDataManager.shared.viewContext
        doc.summaryText = summary

        let existingNotes = doc.userNotes ?? ""
        let aiBlock = "\n\n[AI Summary]\n" + summary
        if existingNotes.isEmpty {
            doc.userNotes = aiBlock.trimmingCharacters(in: .newlines)
        } else if !existingNotes.contains("[AI Summary]") {
            doc.userNotes = existingNotes + aiBlock
        }

        do {
            try context.save()
        } catch {
            print("[VaultSummaryService] Failed to save summary: \(error)")
        }
    }
}
