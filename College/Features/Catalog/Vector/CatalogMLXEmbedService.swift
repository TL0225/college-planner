// CatalogMLXEmbedService.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogMLEmbedError.
// Data: CollegePersistence / repositories when applicable.

import Foundation
@preconcurrency import MLX
import MLXEmbedders
import MLXLMCommon

enum CatalogMLEmbedError: Error, Sendable {
    case emptyTokenization
    case missingModelContainer
    case requiresAppleSilicon(String)
}

/// Thin accessor over MLX's global Metal allocator so the rest of the app can report and
/// reclaim GPU memory without importing MLX everywhere.
///
/// Important: MLX keeps freed Metal buffers in a reuse *cache* (bounded by
/// `MLX.Memory.cacheLimit`, which defaults large on high-RAM Macs) rather than returning
/// them to the OS. So once any model/embedder has run, several hundred MB can stay resident
/// after unload until ``clearCache()`` is called. We only ever touch MLX after it has been
/// initialized (`wasInitialized`) so reading these counters never forces Metal to spin up.
enum MLXRuntimeMemory {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var initialized = false

    static var wasInitialized: Bool {
        lock.lock(); defer { lock.unlock() }
        return initialized
    }

    /// Call once MLX has actually loaded weights / run a graph this session.
    static func markInitialized() {
        lock.lock(); initialized = true; lock.unlock()
    }

    /// Bytes held by live `MLXArray`s. 0 when nothing is loaded.
    static var activeBytes: Int { wasInitialized ? MLX.Memory.activeMemory : 0 }

    /// Bytes parked in MLX's reuse cache (freed but not returned to the OS).
    static var cacheBytes: Int { wasInitialized ? MLX.Memory.cacheMemory : 0 }

    /// Returns the MLX reuse cache to the OS. Safe no-op when MLX was never used.
    static func clearCache() {
        guard wasInitialized else { return }
        MLX.Memory.clearCache()
    }
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
    private var loadedDevice: Device?

    func reset() {
        let hadContainer = container != nil
        container = nil
        loadedDirectory = nil
        loadedDevice = nil
        // Return the embedder's parked Metal buffers to the OS; otherwise they stay resident
        // in MLX's reuse cache long after the model reference is dropped.
        if hadContainer {
            MLXRuntimeMemory.clearCache()
        }
    }

    /// Sentence embedding from the local MLX bundle. ``MLXTaskQueue`` is acquired here (single owner for GPU serialization).
    func embedNormalized(
        text: String,
        modelDirectory: URL,
        priority: MLXTaskPriority = .utility,
        mlxDevice: Device? = nil
    ) async throws -> [Float] {
        try await BackgroundServiceOnDemand.runThrowing(id: "catalog_mlx_embed") {
            try await CatalogMLXEmbedService.shared.embedNormalizedImpl(
                text: text,
                modelDirectory: modelDirectory,
                priority: priority,
                mlxDevice: mlxDevice
            )
        }
    }

    func embedNormalizedImpl(
        text: String,
        modelDirectory: URL,
        priority: MLXTaskPriority = .utility,
        mlxDevice: Device? = nil
    ) async throws -> [Float] {
        try await MLXTaskQueue.shared.run(priority: priority) {
            try await self.embedNormalizedUnqueued(
                text: text,
                modelDirectory: modelDirectory,
                mlxDevice: mlxDevice
            )
        }
    }

    private func embedNormalizedUnqueued(
        text: String,
        modelDirectory: URL,
        mlxDevice: Device?
    ) async throws -> [Float] {
        let run: () async throws -> [Float] = { [self] in
            guard AppleSiliconPlatform.isMLXCompatible else {
                throw CatalogMLEmbedError.requiresAppleSilicon(AppleSiliconPlatform.mlxRequirementMessage)
            }
            if self.container == nil || self.loadedDirectory != modelDirectory || self.loadedDevice != mlxDevice {
                self.container = try await EmbedderModelFactory.shared.loadContainer(
                    from: modelDirectory,
                    using: MLXTokenizerBridge.localDirectoryLoader
                )
                MLXRuntimeMemory.markInitialized()
                self.loadedDirectory = modelDirectory
                self.loadedDevice = mlxDevice
            }
            guard let container = self.container else { throw CatalogMLEmbedError.missingModelContainer }

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

        return try await run()
    }
}
