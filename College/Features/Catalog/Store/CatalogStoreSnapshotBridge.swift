// CatalogStoreSnapshotBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogStoreSnapshotBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Registers the active local store catalog school after ingest (Phase 7f — no local store snapshot copy).
@MainActor
enum CatalogStoreSnapshotBridge {
    /// Opens the per-school catalog container and resolves the university row by name.
    @discardableResult
    static func attachUniversity(
        named universityName: String,
        appDataStore: AppDataStore = .shared,
        activate: Bool = false
    ) -> (CatalogRepository, UUID)? {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: trimmed)
        do {
            try appDataStore.setActiveCatalogSchoolID(schoolID)
        } catch {
            AppLogger.shared.error("CatalogStoreSnapshotBridge: failed to open catalog store: \(error)")
            return nil
        }

        guard let repo = appDataStore.catalogRepository else { return nil }

        let university: University?
        if let exact = try? repo.fetchUniversity(named: trimmed) {
            university = exact
        } else {
            university = (try? repo.fetchUniversities())?.first {
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }
        }
        guard let university else { return nil }

        if activate {
            do {
                try repo.activateUniversity(id: university.id, name: trimmed)
                try appDataStore.catalogSave()
                CatalogStoreCoordinator.shared.upsertRegistryRecord(
                    schoolID: schoolID,
                    universityID: university.id,
                    universityName: trimmed
                )
            } catch {
                AppLogger.shared.error("CatalogStoreSnapshotBridge: failed to activate university: \(error)")
            }
        }

        return (repo, university.id)
    }

    /// Resolves a catalog repository for reads, opening the catalog partition when needed.
    /// Catalog rows live in the unified profile store; this must work even when the partition gate was never opened at launch.
    @discardableResult
    static func catalogRepositoryForUniversity(
        named universityName: String,
        appDataStore: AppDataStore = .shared,
        activate: Bool = false
    ) -> (CatalogRepository, UUID)? {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let attached = attachUniversity(named: trimmed, appDataStore: appDataStore, activate: activate) {
            return attached
        }

        let repo = CatalogRepository(context: appDataStore.profileContext)
        let university = (try? repo.fetchUniversity(named: trimmed))
            ?? (try? repo.fetchUniversities())?.first(where: {
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            })
        guard let university else { return nil }

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: trimmed)
        try? appDataStore.setActiveCatalogSchoolID(schoolID)
        return (repo, university.id)
    }

    static func materializePerSchoolCatalogSnapshot(
        universityName: String,
        appDataStore: AppDataStore = .shared
    ) {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard attachUniversity(named: trimmed, appDataStore: appDataStore, activate: true) != nil else {
            return
        }
        _ = try? appDataStore.catalogSave()
    }
}
