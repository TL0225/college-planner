// CatalogVectorIndexer.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogVectorIndexError.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Projects catalog rows into ``CatalogVectorStore`` with MLX-gated embeddings (local store-only).
actor CatalogVectorIndexer {
    static let shared = CatalogVectorIndexer()

    private(set) var isIndexing: Bool = false
    private var currentUniversityID: UUID?

    private static func readyKey(_ id: UUID) -> String { "catalog.vectorIndex.\(id.uuidString).ready" }
    private static func versionKey(_ id: UUID) -> String { "catalog.vectorIndex.\(id.uuidString).embeddingVersion" }

    static func indexReady(for universityID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: readyKey(universityID))
    }

    static func storedEmbeddingVersion(for universityID: UUID) -> String? {
        UserDefaults.standard.string(forKey: versionKey(universityID))
    }

    /// Clears all `catalog.vectorIndex.*` readiness / version keys (e.g. after a full catalog wipe).
    static func eraseAllIndexCompletionFlags() {
        let defaults = UserDefaults.standard
        let domainName = Bundle.main.bundleIdentifier ?? "College"
        guard let domain = defaults.persistentDomain(forName: domainName) else { return }
        for key in domain.keys where key.hasPrefix("catalog.vectorIndex.") {
            defaults.removeObject(forKey: key)
        }
    }

    func runFullReindex(universityID: UUID, reason: String) async {
        guard !isIndexing else { return }
        let reindexSignpost = PerformanceSignposts.beginCatalogVectorReindex(
            universityID: universityID,
            reason: reason
        )
        isIndexing = true
        currentUniversityID = universityID
        UserDefaults.standard.set(false, forKey: Self.readyKey(universityID))
        await MainActor.run { CatalogEmbedMemoryLifecycle.shared.cancelIdleRelease() }
        defer {
            PerformanceSignposts.endCatalogVectorReindex(reindexSignpost)
            isIndexing = false
            currentUniversityID = nil
            Task { @MainActor in
                CatalogEmbedMemoryLifecycle.shared.scheduleIdleRelease()
            }
        }

        do {
            let coursePageSize = 80
            let pageSize = 200
            let version = CatalogEmbeddingRuntime.embeddingVersion
            var processed = 0

            guard let swiftContainer = await Self.resolveCatalogStoreContainer(universityID: universityID) else {
                throw CatalogVectorIndexError.missingCatalogStore
            }
            let reader = CatalogStoreIndexReader(container: swiftContainer)
            guard try await reader.hasIndexedSources(universityID: universityID) else {
                throw CatalogVectorIndexError.emptyCatalog
            }

            let estimatedTotal = max(
                try await reader.estimatedChunkSourceCount(universityID: universityID),
                1
            )
            try await CatalogVectorStore.shared.deleteAll(universityId: universityID)
            processed = try await indexStoreCoursePages(
                reader: reader,
                universityID: universityID,
                pageSize: coursePageSize,
                version: version,
                processed: processed,
                progressTotal: estimatedTotal
            )
            processed = try await indexStoreDegreeRequirementPages(
                reader: reader,
                universityID: universityID,
                pageSize: pageSize,
                version: version,
                processed: processed,
                progressTotal: estimatedTotal
            )
            processed = try await indexStorePolicyDocumentPages(
                reader: reader,
                universityID: universityID,
                pageSize: pageSize,
                version: version,
                processed: processed,
                progressTotal: estimatedTotal
            )

            UserDefaults.standard.set(true, forKey: Self.readyKey(universityID))
            UserDefaults.standard.set(version, forKey: Self.versionKey(universityID))
            await MainActor.run {
                CatalogMenuBarProgressNotifier.postSucceeded(title: "Search index complete")
            }
            DebugLogger.shared.log(
                "Catalog vector index rebuilt: university=\(universityID) chunks=\(processed) reason=\(reason)",
                category: .system,
                level: .info
            )
        } catch {
            DebugLogger.shared.log(
                "Catalog vector index failed: \(error.localizedDescription)",
                category: .system,
                level: .error
            )
            UserDefaults.standard.set(false, forKey: Self.readyKey(universityID))
            await MainActor.run {
                CatalogMenuBarProgressNotifier.postFailed(message: "Search index failed")
            }
        }
    }

    func isRebuilding(universityID: UUID) -> Bool {
        isIndexing && currentUniversityID == universityID
    }

    private enum CatalogVectorIndexError: Error {
        case missingCatalogStore
        case emptyCatalog
    }

    private func embedAndUpsert(
        chunk: CatalogChunkProjection.IndexedChunk,
        version: String,
        processed: Int,
        progressTotal: Int
    ) async throws -> Int {
        let vector = try await CatalogEmbeddingRuntime.shared.embed(text: chunk.ftsBody, priority: .utility)
        let embData = vector.withUnsafeBufferPointer { buf in
            Data(bytes: buf.baseAddress!, count: buf.count * MemoryLayout<Float>.size)
        }
        try await CatalogVectorStore.shared.upsert(
            chunkId: chunk.chunkId,
            universityId: chunk.universityID,
            sourceKind: chunk.sourceKind,
            ftsBody: chunk.ftsBody,
            metadataJSON: chunk.metadataJSON,
            contentHash: chunk.contentHash,
            embeddingVersion: version,
            embedding: embData,
            courseCode: chunk.courseCode,
            programURL: chunk.programURL,
            requirementCategory: chunk.requirementCategory,
            catalogScope: chunk.catalogScope
        )
        let next = processed + 1
        await MainActor.run {
            CatalogMenuBarProgressNotifier.postCountProgress(
                completed: next,
                total: progressTotal,
                title: "Building semantic index",
                stage: "Search index"
            )
        }
        if next % 32 == 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
        return next
    }

    private actor CatalogStoreIndexReader {
        let container: ModelContainer

        init(container: ModelContainer) {
            self.container = container
        }

        func hasIndexedSources(universityID: UUID) throws -> Bool {
            let context = ModelContext(container)
            var courseDescriptor = FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { course in
                    course.university?.id == universityID && course.isArchived == false
                }
            )
            courseDescriptor.fetchLimit = 1
            if try !context.fetch(courseDescriptor).isEmpty { return true }

            var policyDescriptor = FetchDescriptor<CatalogPolicyDocument>(
                predicate: #Predicate { policy in
                    policy.university?.id == universityID
                }
            )
            policyDescriptor.fetchLimit = 1
            return try !context.fetch(policyDescriptor).isEmpty
        }

        func estimatedChunkSourceCount(universityID: UUID) throws -> Int {
            let context = ModelContext(container)
            let courseCount = try context.fetchCount(
                FetchDescriptor<CourseCatalog>(
                    predicate: #Predicate { course in
                        course.university?.id == universityID && course.isArchived == false
                    }
                )
            )
            let degreeCount = try context.fetchCount(
                FetchDescriptor<CatalogDegreeRequirement>(
                    predicate: #Predicate { requirement in
                        requirement.university?.id == universityID
                    }
                )
            )
            let policyCount = try context.fetchCount(
                FetchDescriptor<CatalogPolicyDocument>(
                    predicate: #Predicate { policy in
                        policy.university?.id == universityID
                    }
                )
            )
            return courseCount + degreeCount + policyCount
        }

        func courseChunks(universityID: UUID, offset: Int, pageSize: Int) throws -> [CatalogChunkProjection.IndexedChunk] {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { course in
                    course.university?.id == universityID && course.isArchived == false
                },
                sortBy: [SortDescriptor(\.courseCode, order: .forward)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            return try context.fetch(descriptor).flatMap { CatalogChunkProjection.chunks(from: $0) }
        }

        func degreeRequirementChunks(universityID: UUID, offset: Int, pageSize: Int) throws -> [CatalogChunkProjection.IndexedChunk] {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
                predicate: #Predicate { requirement in
                    requirement.university?.id == universityID
                },
                sortBy: [SortDescriptor(\.sectionOrder, order: .forward)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            return try context.fetch(descriptor).flatMap { CatalogChunkProjection.chunks(from: $0) }
        }

        func policyDocumentChunks(universityID: UUID, offset: Int, pageSize: Int) throws -> [CatalogChunkProjection.IndexedChunk] {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<CatalogPolicyDocument>(
                predicate: #Predicate { policy in
                    policy.university?.id == universityID
                },
                sortBy: [SortDescriptor(\.navTitle, order: .forward)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            return try context.fetch(descriptor).flatMap { CatalogChunkProjection.chunks(from: $0) }
        }
    }

    @MainActor
    private static func resolveCatalogStoreContainer(universityID: UUID) -> ModelContainer? {
        let registry = CatalogStoreCoordinator.shared.loadRegistry()
        guard let record = registry.first(where: { $0.universityID == universityID }) else {
            return nil
        }
        let store = AppDataStore.shared
        if store.activeCatalogSchoolID == record.schoolID, let container = store.activeCatalogContainer {
            return container
        }
        return try? CollegeModelContainerFactory.makeCatalogContainer(schoolID: record.schoolID)
    }

    private func indexStoreCoursePages(
        reader: CatalogStoreIndexReader,
        universityID: UUID,
        pageSize: Int,
        version: String,
        processed: Int,
        progressTotal: Int
    ) async throws -> Int {
        var processed = processed
        var offset = 0
        while true {
            let pageChunks = try await reader.courseChunks(
                universityID: universityID,
                offset: offset,
                pageSize: pageSize
            )
            if pageChunks.isEmpty { break }
            for chunk in pageChunks {
                processed = try await embedAndUpsert(
                    chunk: chunk,
                    version: version,
                    processed: processed,
                    progressTotal: progressTotal
                )
            }
            offset += pageSize
        }
        return processed
    }

    private func indexStoreDegreeRequirementPages(
        reader: CatalogStoreIndexReader,
        universityID: UUID,
        pageSize: Int,
        version: String,
        processed: Int,
        progressTotal: Int
    ) async throws -> Int {
        var processed = processed
        var offset = 0
        while true {
            let pageChunks = try await reader.degreeRequirementChunks(
                universityID: universityID,
                offset: offset,
                pageSize: pageSize
            )
            if pageChunks.isEmpty { break }
            for chunk in pageChunks {
                processed = try await embedAndUpsert(
                    chunk: chunk,
                    version: version,
                    processed: processed,
                    progressTotal: progressTotal
                )
            }
            offset += pageSize
        }
        return processed
    }

    private func indexStorePolicyDocumentPages(
        reader: CatalogStoreIndexReader,
        universityID: UUID,
        pageSize: Int,
        version: String,
        processed: Int,
        progressTotal: Int
    ) async throws -> Int {
        var processed = processed
        var offset = 0
        while true {
            let pageChunks = try await reader.policyDocumentChunks(
                universityID: universityID,
                offset: offset,
                pageSize: pageSize
            )
            if pageChunks.isEmpty { break }
            for chunk in pageChunks {
                processed = try await embedAndUpsert(
                    chunk: chunk,
                    version: version,
                    processed: processed,
                    progressTotal: progressTotal
                )
            }
            offset += pageSize
        }
        return processed
    }
}
