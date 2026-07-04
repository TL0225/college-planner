// AppDataStoreBootstrap.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStoreBootstrap.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Opens the active local store catalog partition when the app shell starts (Phase 7f).
enum AppDataStoreBootstrap {
    @MainActor
    static func syncActiveCatalogFromStore() {
        let persistence = CollegePersistence.shared

        // Re-open the catalog gate from the persisted active-school id *first*. `getActiveUniversity()`
        // is itself gated behind the catalog partition (`activeCatalogSchoolID`), so at a cold launch
        // it is always nil — restoring the persisted id breaks that chicken-and-egg.
        if let persistedSchoolID = UserDefaults.standard.string(forKey: AppDataStoreBridge.activeCatalogSchoolIDKey),
           !persistedSchoolID.isEmpty {
            try? AppDataStore.shared.setActiveCatalogSchoolID(persistedSchoolID)
        }

        // Resolve the school name: prefer the now-reachable active university, then fall back to the
        // declared school on the profile / academic profile (those live in the always-reachable
        // profile partition, so they survive even when the catalog gate was lost).
        let resolvedName = (persistence.getActiveUniversity()?.name ?? declaredSchoolName(persistence))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Never erase a valid active-school just because the name couldn't be resolved this launch.
        guard !resolvedName.isEmpty else { return }

        // (Re)attach + activate + persist the active catalog school so catalog-backed data
        // (requirements, programs, courses) is reachable again after relaunch.
        _ = persistence.setActiveUniversity(named: resolvedName)
    }

    @MainActor
    private static func declaredSchoolName(_ persistence: CollegePersistence) -> String? {
        if let name = persistence.profile?.collegeName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        for academic in persistence.academicProfiles {
            if let name = academic.collegeName ?? academic.profile?.collegeName,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return nil
    }
}