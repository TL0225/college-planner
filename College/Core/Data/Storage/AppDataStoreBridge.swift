// AppDataStoreBridge.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStoreBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Keeps `AppDataStore` catalog partition aligned with the active local store university / catalog school.
enum AppDataStoreBridge {
    static let activeCatalogSchoolIDKey = "catalog.activeSchoolID"
    static let legacyActiveCatalogUniversityIDKey = "catalog.activeUniversityID"
    nonisolated static func syncActiveCatalogSchool(universityName: String?) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                syncActiveCatalogSchoolOnMain(universityName: universityName)
            }
        } else {
            DispatchQueue.main.async {
                syncActiveCatalogSchoolOnMain(universityName: universityName)
            }
        }
    }

    @MainActor
    private static func syncActiveCatalogSchoolOnMain(universityName: String?) {
        let trimmed = universityName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            UserDefaults.standard.removeObject(forKey: activeCatalogSchoolIDKey)
            try? AppDataStore.shared.setActiveCatalogSchoolID(nil)
            return
        }

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: trimmed)
        UserDefaults.standard.set(schoolID, forKey: activeCatalogSchoolIDKey)
        do {
            try AppDataStore.shared.setActiveCatalogSchoolID(schoolID)
        } catch {
            AppLogger.shared.error("AppDataStoreBridge: failed to open catalog container for \(schoolID): \(error)")
        }
    }
}