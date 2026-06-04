// AppDataStore.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStore.
// Data: CollegePersistence / repositories when applicable.

import Combine
import Foundation
import SwiftData

/// local store-facing store skeleton (Phase 7a). Coexists with `CollegePersistence` until Phase 7f.
@MainActor
final class AppDataStore: ObservableObject {
    static let shared = AppDataStore()

    let profileContainer: ModelContainer
    @Published private(set) var activeCatalogContainer: ModelContainer?
    @Published private(set) var activeCatalogSchoolID: String?

    /// Mirrors `CollegePersistence.profileRevision`.
    @Published private(set) var profileRevision: Int = 0
    /// Mirrors `CollegePersistence.catalogDataRevision`.
    @Published private(set) var catalogDataRevision: Int = 0

    var profileContext: ModelContext {
        profileContainer.mainContext
    }

    var activeCatalogContext: ModelContext? {
        activeCatalogContainer?.mainContext
    }

    var profileRepository: ProfileRepository {
        ProfileRepository(context: profileContext)
    }

    var catalogRepository: CatalogRepository? {
        guard let activeCatalogContext else { return nil }
        return CatalogRepository(context: activeCatalogContext)
    }

    var calendarRepository: CalendarRepository {
        CalendarRepository(context: profileContext)
    }

    var vaultRepository: VaultRepository {
        VaultRepository(context: profileContext)
    }

    var careerRepository: CareerRepository {
        CareerRepository(context: profileContext)
    }

    init(profileContainer: ModelContainer? = nil) {
        if let profileContainer {
            self.profileContainer = profileContainer
        } else if CollegeTestRuntime.isUnitTestProcess {
            self.profileContainer = (try! CollegeModelContainerFactory.makeProfileContainer(inMemory: true))
        } else {
            self.profileContainer = (try! CollegeModelContainerFactory.makeProfileContainer())
        }
    }

    func bumpProfileRevision() {
        profileRevision &+= 1
        objectWillChange.send()
    }

    func bumpCatalogDataRevision() {
        catalogDataRevision &+= 1
        objectWillChange.send()
    }

    /// Opens (or reuses) the per-school catalog container at `CatalogStoreCoordinator` layout paths.
    func setActiveCatalogSchoolID(_ schoolID: String?) throws {
        guard let schoolID, !schoolID.isEmpty else {
            activeCatalogContainer = nil
            activeCatalogSchoolID = nil
            return
        }
        if activeCatalogSchoolID == schoolID, activeCatalogContainer != nil {
            return
        }
        activeCatalogContainer = try CollegeModelContainerFactory.makeCatalogContainer(schoolID: schoolID)
        activeCatalogSchoolID = schoolID
        bumpCatalogDataRevision()
    }

    @discardableResult
    func profileSave() throws -> Bool {
        guard profileContext.hasChanges else { return false }
        try profileContext.save()
        bumpProfileRevision()
        return true
    }

    @discardableResult
    func catalogSave() throws -> Bool {
        guard let context = activeCatalogContext, context.hasChanges else { return false }
        try context.save()
        bumpCatalogDataRevision()
        return true
    }

    /// Drops in-memory catalog container under memory pressure; school ID retained for reopen.
    func releaseActiveCatalogContainerForMemoryPressure() {
        activeCatalogContainer = nil
        bumpCatalogDataRevision()
    }

    /// Attaches an in-memory catalog container for catalog-focused unit tests.
    func useInMemoryCatalogForUnitTesting(schoolID: String = "test-school") throws {
        guard CollegeTestRuntime.isUnitTestProcess else { return }
        activeCatalogContainer = try CollegeModelContainerFactory.makeCatalogContainer(
            schoolID: schoolID,
            inMemory: true
        )
        activeCatalogSchoolID = schoolID
        bumpCatalogDataRevision()
    }
}