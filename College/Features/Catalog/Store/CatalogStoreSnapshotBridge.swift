// CatalogStoreSnapshotBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogStoreSnapshotBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Registers the active local store catalog school after ingest (Phase 7f — no local store snapshot copy).
@MainActor
enum CatalogStoreSnapshotBridge {
    static func materializePerSchoolCatalogSnapshot(
        universityName: String,
        appDataStore: AppDataStore = .shared
    ) {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: trimmed)
        do {
            try appDataStore.setActiveCatalogSchoolID(schoolID)
        } catch {
            AppLogger.shared.error("CatalogStoreSnapshotBridge: failed to open catalog store: \(error)")
            return
        }

        guard let repo = appDataStore.catalogRepository,
              let active = try? repo.fetchActiveUniversity(),
              active.name.caseInsensitiveCompare(trimmed) == .orderedSame else {
            return
        }

        _ = try? appDataStore.catalogSave()
        CatalogStoreCoordinator.shared.upsertRegistryRecord(
            schoolID: schoolID,
            universityID: active.id,
            universityName: trimmed
        )
    }
}
