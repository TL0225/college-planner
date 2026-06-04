// CatalogMLXEmbedService.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogMLEmbedError.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon

enum CatalogMLEmbedError: Error, Sendable {
    case emptyTokenization
    case missingModelContainer
    case requiresAppleSilicon(String)
}

/// On-disk MLX sentence embeddings (mlx-swift-lm **MLXEmbedders** only — avoids `ModelContainer` ambiguity with MLXLMCommon).
enum CatalogMLXEmbedPaths {
    /// `Application Support/College/CatalogEmbed/` — staged overrides / updates after first launch.
    nonisolated static func defaultModelDirectoryURL() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("CatalogEmbed", isDirectory: true)
    }

    /// Bundle-shipped `CatalogEmbed` folder (see `README.md` in `College/CatalogEmbed/`).
    nonisolated static func bundledModelDirectoryURL() -> URL? {
        Bundle.main.url(forResource: "CatalogEmbed", withExtension: nil)
    }

    /// Priority 1: app bundle `CatalogEmbed`; priority 2: Application Support staged copy.
    nonisolated static func resolvedModelDirectoryURL() -> URL? {
        if let bundleURL = bundledModelDirectoryURL(),
           hasSentenceModelBundle(at: bundleURL) {
            return bundleURL
        }
        let appSupportURL = defaultModelDirectoryURL()
        if hasSentenceModelBundle(at: appSupportURL) {
            return appSupportURL
        }
        return nil
    }

    nonisolated static func hasSentenceModelBundle(at directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path)
    }
}

actor CatalogMLXEmbedService {
    static let shared = CatalogMLXEmbedService()

    private var container: EmbedderModelContainer?
    private var loadedDirectory: URL?

    func reset() {
        container = nil
        loadedDirectory = nil
    }

    /// Sentence embedding from the local MLX bundle. ``MLXTaskQueue`` is acquired here (single owner for GPU serialization).
    func embedNormalized(text: String, modelDirectory: URL, priority: MLXTaskPriority = .utility) async throws -> [Float] {
        try await MLXTaskQueue.shared.run(priority: priority) {
            try await self.embedNormalizedUnqueued(text: text, modelDirectory: modelDirectory)
        }
    }

    private func embedNormalizedUnqueued(text: String, modelDirectory: URL) async throws -> [Float] {
        guard AppleSiliconPlatform.isSupported else {
            throw CatalogMLEmbedError.requiresAppleSilicon(AppleSiliconPlatform.requirementMessage)
        }
        if container == nil || loadedDirectory != modelDirectory {
            container = try await EmbedderModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: MLXTokenizerBridge.localDirectoryLoader
            )
            loadedDirectory = modelDirectory
        }
        guard let container else { throw CatalogMLEmbedError.missingModelContainer }

        return try await container.perform { context in
            let tokens = context.tokenizer.encode(text: text)
            guard !tokens.isEmpty else { throw CatalogMLEmbedError.emptyTokenization }

            let maxLen = 512
            let capped = Array(tokens.prefix(maxLen))
            let inputIds = MLXArray(capped).expandedDimensions(axis: 0)
            let mask = ones(like: inputIds)
            let output = context.model(
                inputIds,
                positionIds: nil,
                tokenTypeIds: nil,
                attentionMask: mask
            )
            let pooled = context.pooling(output, mask: mask, normalize: true)
            eval(pooled)
            let floats = pooled.asArray(Float.self)
            guard !floats.isEmpty else { throw CatalogMLEmbedError.emptyTokenization }
            return floats
        }
    }
}
