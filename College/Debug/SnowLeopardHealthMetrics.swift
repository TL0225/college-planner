// SnowLeopardHealthMetrics.swift
// Feature: Debug
// Purpose: Observable Snow Leopard remediation metrics (DEBUG + diagnostics export).

import Foundation
import SwiftData

/// Cross-cutting health counters for the Snow Leopard scoreboard and diagnostics bundle.
enum SnowLeopardHealthMetrics {
    struct Snapshot: Codable, Sendable {
        var gitCommit: String?
        var coldLaunchMS: Double?
        var saveDurationMS: Double?
        var refreshAllCallCount: Int
        var refreshProfileCachesCallCount: Int
        var catalogLoadMS: Double?
        var vaultImportMS: Double?
        var translationCacheEntryCount: Int
        var vaultThumbnailCacheEntryCount: Int
        var faviconMemoryEntryCount: Int
        var webShortcutCoordinatorCount: Int
        var vaultHierarchyViolationCount: Int
        var vectorIndexReadyUniversities: Int
        var storeOpenError: String?
        var capturedAt: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _coldLaunchMS: Double?
    nonisolated(unsafe) private static var _saveDurationMS: Double?
    nonisolated(unsafe) private static var _refreshAllCallCount = 0
    nonisolated(unsafe) private static var _refreshProfileCachesCallCount = 0
    nonisolated(unsafe) private static var _catalogLoadMS: Double?
    nonisolated(unsafe) private static var _vaultImportMS: Double?
    nonisolated(unsafe) private static var _vaultHierarchyViolationCount = 0

    static func recordColdLaunch(milliseconds: Double) {
        lock.lock()
        _coldLaunchMS = milliseconds
        lock.unlock()
    }

    static func recordSaveDuration(milliseconds: Double) {
        lock.lock()
        _saveDurationMS = milliseconds
        lock.unlock()
    }

    static func recordRefreshAll() {
        lock.lock()
        _refreshAllCallCount += 1
        lock.unlock()
    }

    static func recordRefreshProfileCaches() {
        lock.lock()
        _refreshProfileCachesCallCount += 1
        lock.unlock()
    }

    static func recordCatalogLoad(milliseconds: Double) {
        lock.lock()
        _catalogLoadMS = milliseconds
        lock.unlock()
    }

    static func recordVaultImport(milliseconds: Double) {
        lock.lock()
        _vaultImportMS = milliseconds
        lock.unlock()
    }

    static func recordVaultHierarchyViolations(_ count: Int) {
        lock.lock()
        _vaultHierarchyViolationCount = count
        lock.unlock()
    }

    @MainActor
    static func snapshot(storeOpenError: String? = nil) -> Snapshot {
        lock.lock()
        let launch = _coldLaunchMS
        let save = _saveDurationMS
        let refreshAll = _refreshAllCallCount
        let refreshProfile = _refreshProfileCachesCallCount
        let catalog = _catalogLoadMS
        let vaultImport = _vaultImportMS
        let violations = _vaultHierarchyViolationCount
        lock.unlock()

        let universities = (try? AppDataStore.shared.profileContext.fetch(FetchDescriptor<University>())) ?? []
        let readyCount = universities.filter { CatalogVectorIndexer.indexReady(for: $0.id) }.count

        let formatter = ISO8601DateFormatter()
        return Snapshot(
            gitCommit: Bundle.main.infoDictionary?["GitCommitHash"] as? String,
            coldLaunchMS: launch,
            saveDurationMS: save,
            refreshAllCallCount: refreshAll,
            refreshProfileCachesCallCount: refreshProfile,
            catalogLoadMS: catalog,
            vaultImportMS: vaultImport,
            translationCacheEntryCount: TranslationCache.shared.entryCount,
            vaultThumbnailCacheEntryCount: VaultThumbnailCache.shared.entryCount,
            faviconMemoryEntryCount: FaviconStore.shared.memoryEntryCount,
            webShortcutCoordinatorCount: WebShortcutCoordinatorPool.activeCoordinatorCount,
            vaultHierarchyViolationCount: violations,
            vectorIndexReadyUniversities: readyCount,
            storeOpenError: storeOpenError ?? AppDataStore.shared.storeOpenError,
            capturedAt: formatter.string(from: Date())
        )
    }

    @MainActor
    static func writeJSON(to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot())
        try data.write(to: url, options: [.atomic])
    }
}
