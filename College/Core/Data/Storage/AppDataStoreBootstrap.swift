// AppDataStoreBootstrap.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStoreBootstrap.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Opens the active local store catalog partition when the app shell starts (Phase 7f).
enum AppDataStoreBootstrap {
    @MainActor
    static func syncActiveCatalogFromStore() {
        let universityName = CollegePersistence.shared.getActiveUniversity()?.name
        AppDataStoreBridge.syncActiveCatalogSchool(universityName: universityName)
    }
}