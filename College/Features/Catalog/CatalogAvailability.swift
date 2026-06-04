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
        guard let repo = appDataStore.catalogRepository else { return false }
        guard let active = try? repo.fetchActiveUniversity(),
              active.name.caseInsensitiveCompare(trimmed) == .orderedSame else {
            return false
        }
        return (try? repo.hasPrograms(universityID: active.id)) == true
    }
}
