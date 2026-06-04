// CatalogSelectedProgramsStore.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSelectedProgramsStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persistent record of which catalog programs the user has hand-picked for selective deep scraping.
///
/// The settings UI populates this store from `CatalogProgramRequirementsHydrator.SelectableProgram.id`
/// values (a composite of `universityName | catalogLevel | degreeLabel`). The store stays UI-agnostic so
/// future surfaces (Onboarding, Overview prompt, command palette) can reuse it.
enum CatalogSelectedProgramsStore {
    private static let storageKey = "catalog.selectedProgramIDs.v1"

    /// All program identifiers the user has selected, across schools.
    static func allSelected() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        return Set(raw)
    }

    /// Replaces the persisted selection with `ids`.
    static func replace(_ ids: Set<String>) {
        let array = Array(ids).sorted()
        UserDefaults.standard.set(array, forKey: storageKey)
    }

    /// Removes any persisted identifiers that aren't in `validIDs`.
    /// Use after refreshing the catalog program list to drop stale rows.
    static func prune(validIDs: Set<String>) -> Set<String> {
        let pruned = allSelected().intersection(validIDs)
        replace(pruned)
        return pruned
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
