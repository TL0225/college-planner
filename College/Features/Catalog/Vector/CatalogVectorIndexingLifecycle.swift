// CatalogVectorIndexingLifecycle.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogVectorIndexingLifecycle.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Registers for `Notification.Name.catalogDataDidCommit` and debounces full vector reindexes.
enum CatalogVectorIndexingLifecycle {
    nonisolated(unsafe) private static var observer: NSObjectProtocol?
    nonisolated(unsafe) private static var debounceTask: Task<Void, Never>?

    /// Wipes SQLite vectors, index readiness defaults, and unloads any cached MLX embedder (catalog reset / active school cleared).
    static func invalidateAllVectorState(reason: String) async {
        debounceTask?.cancel()
        debounceTask = nil
        await CatalogMLXEmbedService.shared.reset()
        try? await CatalogVectorStore.shared.deleteAllRows()
        CatalogVectorIndexer.eraseAllIndexCompletionFlags()
        await MainActor.run {
            DebugLogger.shared.log(
                "Catalog vector state invalidated: \(reason)",
                category: .system,
                level: .info
            )
        }
    }

    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .catalogDataDidCommit,
            object: nil,
            queue: .main
        ) { note in
            let universityIDString = note.userInfo?["universityID"] as? String
            let reason = (note.userInfo?["reason"] as? String) ?? "unknown"
            Task { @MainActor in
                await Self.handleCatalogDataDidCommit(universityIDString: universityIDString, reason: reason)
            }
        }
    }

    @MainActor
    private static func handleCatalogDataDidCommit(universityIDString: String?, reason: String) async {
        guard let raw = universityIDString,
              let uid = UUID(uuidString: raw) else { return }
        debounceTask?.cancel()
        debounceTask = Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await CatalogVectorIndexer.shared.runFullReindex(universityID: uid, reason: reason)
        }
    }
}
