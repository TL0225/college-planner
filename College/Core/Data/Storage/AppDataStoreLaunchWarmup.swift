// AppDataStoreLaunchWarmup.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStoreLaunchWarmup.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Launch-time local store container warm (Phase 7c); coexists with local store preload.
@MainActor
enum AppDataStoreLaunchWarmup {
    private static var didWarmProfileContainer = false

    static func prepareIfNeeded() {
        guard !didWarmProfileContainer else { return }
        didWarmProfileContainer = true
        _ = try? AppDataStore.shared.profileRepository.fetchProfiles(limit: 1)
        AppDataStoreBootstrap.syncActiveCatalogFromStore()
    }
}