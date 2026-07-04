// LaunchBootstrapCache.swift
// Feature: App
// Purpose: App module — LaunchBootstrapCache.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Dedupes local store snapshot fetches invoked from multiple launch preload paths in one process.
@MainActor
enum LaunchBootstrapCache {
    private static var didFetchSemesters = false
    private static var didFetchPlans = false
    private static var didFetchProfile = false
    private static var didFetchVaultDocuments = false

    private static var persistence: CollegePersistence { CollegePersistence.shared }

    static func fetchSemestersIfNeeded() {
        guard !didFetchSemesters else { return }
        didFetchSemesters = true
        persistence.fetchSemesters()
    }

    static func fetchPlansIfNeeded() {
        guard !didFetchPlans else { return }
        didFetchPlans = true
        persistence.fetchPlans()
    }

    static func fetchProfileIfNeeded() {
        guard !didFetchProfile else { return }
        didFetchProfile = true
        _ = persistence.ensurePrimaryProfile()
    }

    static func fetchVaultDocumentsIfNeeded() {
        guard !didFetchVaultDocuments else { return }
        didFetchVaultDocuments = true
        persistence.fetchVaultDocuments()
    }

    static func warmCoreSnapshotsIfNeeded() {
        fetchSemestersIfNeeded()
        fetchPlansIfNeeded()
        fetchProfileIfNeeded()
        fetchVaultDocumentsIfNeeded()
    }
}
