// CatalogAvailability.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogAvailability.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only catalog presence checks (no local store).
@MainActor
enum CatalogAvailability {
    /// True when the active local store catalog has at least one program row for the named school.
    static func hasUniversityCatalog(
        name universityName: String,
        appDataStore: AppDataStore = .shared
    ) -> Bool {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let (repo, universityID) = CatalogStoreSnapshotBridge.attachUniversity(
            named: trimmed,
            appDataStore: appDataStore
        ) else {
            return false
        }
        return (try? repo.hasPrograms(universityID: universityID)) == true
    }
}
