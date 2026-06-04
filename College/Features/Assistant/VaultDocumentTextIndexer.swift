// VaultDocumentTextIndexer.swift
// Feature: Assistant
// Purpose: Assistant module — IndexWork.
// Data: CollegePersistence / repositories when applicable.

// Isolation: `actor VaultDocumentTextIndexer`; `@concurrent` on schedule entry (utility work off MainActor).

import AppKit
import Foundation
import PDFKit
import Vision

/// Extracts vault document text and upserts planner chunks; dual-indexes CoreSpotlight metadata.
actor VaultDocumentTextIndexer {
    static let shared = VaultDocumentTextIndexer()

    private var inFlight: Set<UUID> = []

    @concurrent
    nonisolated func schedule(documentID: UUID) async {
        await VaultDocumentTextIndexer.shared.enqueue(documentID: documentID)
    }

    func enqueue(documentID: UUID) async {
        guard AssistantPlannerIndexingSettings.isIndexingEnabled,
              AssistantPlannerIndexingSettings.isDocumentsIndexingEnabled else { return }
        guard inFlight.insert(documentID).inserted else { return }
        defer { inFlight.remove(documentID) }

        let work = await MainActor.run { Self.prepareIndexWork(documentID: documentID) }
        guard let work else { return }

        VaultSpotlightService.index(work.spotlightItem)

        try? await PlannerVectorStore.shared.deleteChunks(
            sourceType: "vault_document",
            sourceId: documentID.uuidString
        )
        for chunk in work.metadataChunks {
            try? await upsertPlannerChunk(chunk)
        }

        if let readURL = work.readURL {
            let plain = await extractPlainText(fileURL: readURL)
            if !plain.isEmpty {
                let textChunks = PlannerChunkProjection.vaultTextChunks(
                    documentId: documentID,
                    plainText: plain,
                    referenceDate: work.referenceDate
                )
                for chunk in textChunks {
                    try? await upsertPlannerChunk(chunk)
                }
            }
            if work.shouldDeleteTempFile, readURL != work.storedURL {
                try? FileManager.default.removeItem(at: readURL)
            }
        }

        let count = (try? await PlannerVectorStore.shared.chunkCount()) ?? 0
        AssistantPlannerIndexingSettings.markIndexed(chunkCount: count)
    }

    @concurrent
    nonisolated func scheduleBackfill(documentIDs: [UUID]) async {
        for id in documentIDs {
            await schedule(documentID: id)
            await Task.yield()
        }
    }

    private struct IndexWork: Sendable {
        let spotlightItem: VaultSpotlightService.IndexItem
        let metadataChunks: [PlannerChunkProjection.IndexedChunk]
        let readURL: URL?
        let storedURL: URL?
        let shouldDeleteTempFile: Bool
        let referenceDate: Date?
    }

    @MainActor
    private static func prepareIndexWork(documentID: UUID) -> IndexWork? {
        let persistence = CollegePersistence.shared
        guard let doc = try? persistence.vaultRepository.fetchDocument(id: documentID),
              !doc.isFolder else { return nil }

        let tags = (doc.tags ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let storedURL = persistence.urlForVaultDocument(doc)
        let readURL = persistence.decryptedTempURLForStoredRelativePath(
            doc.localRelativePath,
            displayFileName: doc.fileName
        )
        let shouldDeleteTemp: Bool = {
            guard let read = readURL, let stored = storedURL else { return false }
            return read != stored
        }()

        return IndexWork(
            spotlightItem: VaultSpotlightService.IndexItem(
                id: documentID,
                name: doc.customDisplayName ?? doc.fileName,
                category: doc.category,
                tags: tags,
                notes: doc.userNotes,
                addedAt: doc.addedAt,
                fileURL: storedURL
            ),
            metadataChunks: PlannerChunkProjection.vaultMetadataChunks(from: doc),
            readURL: readURL,
            storedURL: storedURL,
            shouldDeleteTempFile: shouldDeleteTemp,
            referenceDate: doc.lastOpenedAt ?? doc.addedAt
        )
    }

    private func upsertPlannerChunk(_ chunk: PlannerChunkProjection.IndexedChunk) async throws {
        let vec = AssistantWebMemoryEmbedding.vector(for: String(chunk.ftsBody.prefix(4_000)))
        let emb = AssistantWebMemoryEmbedding.data(from: vec)
        try await PlannerVectorStore.shared.upsert(
            chunkId: chunk.chunkId,
            sourceType: chunk.sourceType,
            sourceId: chunk.sourceId,
            segmentIndex: chunk.segmentIndex,
            ftsBody: chunk.ftsBody,
            metadataJSON: chunk.metadataJSON,
            contentHash: chunk.contentHash,
            embeddingVersion: PlannerVectorSearchConfig.embeddingVersion,
            referenceDate: chunk.referenceDate,
            embedding: emb
        )
    }

    private func extractPlainText(fileURL: URL) async -> String {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "pdf" {
            return await extractPDFText(fileURL: fileURL)
        }
        if ["txt", "md", "markdown", "csv", "json"].contains(ext) {
            return await Task.detached(priority: .utility) {
                (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            }.value
        }
        if ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"].contains(ext) {
            return await ocrImage(fileURL: fileURL)
        }
        return ""
    }

    private func extractPDFText(fileURL: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let doc = PDFDocument(url: fileURL) else { return "" }
            let pageCount = doc.pageCount
            var parts: [String] = []
            for i in 0..<min(pageCount, 48) {
                if let page = doc.page(at: i), let s = page.string, !s.isEmpty {
                    parts.append(s)
                }
            }
            let joined = parts.joined(separator: "\n")
            if joined.count >= 80 { return joined }
            return Self.ocrPDFPagesSync(doc: doc, maxPages: min(pageCount, 6))
        }.value
    }

    private static func ocrPDFPagesSync(doc: PDFDocument, maxPages: Int) -> String {
        var out: [String] = []
        for i in 0..<maxPages {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
            let image = page.thumbnail(of: size, for: .mediaBox)
            let text = ocrNSImageSync(image)
            if !text.isEmpty { out.append(text) }
        }
        return out.joined(separator: "\n")
    }

    private func ocrImage(fileURL: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: fileURL) else { return "" }
            return Self.ocrNSImageSync(image)
        }.value
    }

    private static func ocrNSImageSync(_ nsImage: NSImage) -> String {
        guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
