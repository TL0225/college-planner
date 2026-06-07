// PersistenceTestHarness.swift
// Feature: Shared
// Purpose: Shared module — Containers.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
@testable import College

/// In-memory local store containers for unit tests (Phase 7g).
@MainActor
enum PersistenceTestHarness {
    struct Containers: @unchecked Sendable {
        let profile: ModelContainer
        let catalog: ModelContainer?

        @MainActor
        var profileContext: ModelContext { profile.mainContext }
        @MainActor
        var catalogContext: ModelContext? { catalog?.mainContext }
    }

    static func makeProfileOnly() throws -> Containers {
        let profile = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        return Containers(profile: profile, catalog: nil)
    }

    static func makeProfileAndCatalog(schoolID: String = "test-school") throws -> Containers {
        let profile = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let catalog = try CollegeModelContainerFactory.makeCatalogContainer(schoolID: schoolID, inMemory: true)
        return Containers(profile: profile, catalog: catalog)
    }

    static func makeUnified() throws -> ModelContainer {
        try CollegeModelContainerFactory.makeUnifiedInMemoryContainer()
    }

    static func makeAppDataStore(profileContainer: ModelContainer? = nil) throws -> AppDataStore {
        let profile: ModelContainer
        if let profileContainer {
            profile = profileContainer
        } else {
            profile = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        }
        return AppDataStore(profileContainer: profile)
    }
}
