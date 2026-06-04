// VaultStoreMirror.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — VaultStoreMirror.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Deprecated dual-write shim (Phase 7f). local store is authoritative; upserts are no-ops.
enum VaultStoreMirror {
    static func upsertVaultDocument(_ entity: Any) { _ = entity }

    static func deleteVaultDocument(id: UUID) {
        onMain {
            try? AppDataStore.shared.vaultRepository.deleteVaultDocument(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    static func flushPendingWrites() {
        onMain {
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    static func performOnMainActor(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }

    static func mirrorVaultDocumentAfterSave(objectID: Any) { _ = objectID }

    private static func onMain(_ work: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { work() }
        }
    }
}