// AppDataStore.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppDataStore.
// Data: CollegePersistence / repositories when applicable.

import Combine
import Foundation
import SwiftData

/// Single SwiftData store for profile, planner, career, vault, and catalog models.
@MainActor
final class AppDataStore: ObservableObject {
    static let shared = AppDataStore()

    let profileContainer: ModelContainer
    @Published private(set) var storeOpenError: String?
    @Published private(set) var activeCatalogSchoolID: String?

    /// Mirrors `CollegePersistence.profileRevision`.
    @Published private(set) var profileRevision: Int = 0
    /// Mirrors `CollegePersistence.catalogDataRevision`.
    @Published private(set) var catalogDataRevision: Int = 0

    var profileContext: ModelContext {
        profileContainer.mainContext
    }

    /// Catalog models live in the same store as profile data.
    var activeCatalogContext: ModelContext? {
        activeCatalogSchoolID == nil ? nil : profileContext
    }

    /// Retained for callers that previously held a separate catalog container reference.
    var activeCatalogContainer: ModelContainer? {
        activeCatalogSchoolID == nil ? nil : profileContainer
    }

    var profileRepository: ProfileRepository {
        ProfileRepository(context: profileContext)
    }

    var catalogRepository: CatalogRepository? {
        guard activeCatalogSchoolID != nil else { return nil }
        return CatalogRepository(context: profileContext)
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
            self.storeOpenError = nil
        } else if CollegeTestRuntime.isUnitTestProcess {
            self.profileContainer = Self.makeInMemoryLaunchContainer()
            self.storeOpenError = nil
        } else {
            let resolved = Self.resolveProfileContainerForLaunch()
            self.profileContainer = resolved.container
            self.storeOpenError = resolved.errorMessage
        }

        if storeOpenError == nil {
            Task(priority: .utility) { @MainActor in
                CollegeUnifiedCatalogStoreMigration.migrateIfNeeded(appDataStore: self)
            }
        }
    }

    private static func resolveProfileContainerForLaunch() -> (container: ModelContainer, errorMessage: String?) {
        let storeURL = CollegeModelContainerFactory.unifiedStoreURL()
        do {
            return (try CollegeModelContainerFactory.makeProfileContainer(), nil)
        } catch var openError {
            let configuration = ModelConfiguration(url: storeURL)
            if CollegeSchemaLegacyStoreRepair.repairStore(
                at: storeURL,
                partition: .unified,
                targetSchema: CollegeModelContainerFactory.unifiedSchema,
                configuration: configuration
            ) {
                do {
                    return (try CollegeModelContainerFactory.makeProfileContainer(), nil)
                } catch {
                    openError = error
                }
            }

            let legacyURL = CollegeModelContainerFactory.legacyProfileStoreURL()
            if FileManager.default.fileExists(atPath: legacyURL.path),
               CollegeSchemaLegacyStoreRepair.repairStore(
                at: legacyURL,
                partition: .unified,
                targetSchema: CollegeModelContainerFactory.unifiedSchema,
                configuration: ModelConfiguration(url: legacyURL)
               ) {
                do {
                    return (try CollegeModelContainerFactory.makeProfileContainer(), nil)
                } catch {
                    openError = error
                }
            }

            if let quarantineURL = ModelStoreMaintenance.quarantineProfileStore(at: storeURL),
               let fresh = try? CollegeModelContainerFactory.makeProfileContainer() {
                let message =
                    "Could not open the existing data store (schema mismatch). "
                    + "Your previous file was moved to \(quarantineURL.lastPathComponent). "
                    + "A new empty store was created."
                Self.logStoreOpenFailure(code: "STORE_QUARANTINED", message: message)
                return (fresh, message)
            }

            if let fresh = try? CollegeModelContainerFactory.makeProfileContainer() {
                let message =
                    "Could not open the existing data store at \(storeURL.path): "
                    + openError.localizedDescription
                    + ". A new empty store was created."
                Self.logStoreOpenFailure(code: "STORE_REPLACED", message: message)
                return (fresh, message)
            }

            let fallback = Self.makeInMemoryLaunchContainer()
            let message =
                "Failed to open unified store at \(storeURL.path): "
                + openError.localizedDescription
                + ". Using an in-memory store for this session only."
            Self.logStoreOpenFailure(code: "STORE_IN_MEMORY_FALLBACK", message: message)
            #if DEBUG
            return (fallback, nil)
            #else
            return (fallback, message)
            #endif
        }
    }

    /// Never `try!` during launch — a failed in-memory container must not crash `CollegePersistence.shared`.
    private static func makeInMemoryLaunchContainer() -> ModelContainer {
        if let container = try? CollegeModelContainerFactory.makeProfileContainer(inMemory: true) {
            return container
        }
        if let container = try? ModelContainer(
            for: CollegeModelContainerFactory.unifiedSchema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) {
            return container
        }
        preconditionFailure("Unable to create an in-memory SwiftData container for launch.")
    }

    private static func logStoreOpenFailure(code: String, message: String) {
        NSLog("AppDataStore: %@", message)
        DiagnosticsEvent.emit(
            subsystem: .app,
            severity: .critical,
            code: code,
            message: message,
            category: "persistence"
        )
    }

    func bumpProfileRevision() {
        profileRevision &+= 1
        objectWillChange.send()
        CollegePersistence.shared.applyProfileRevisionBumpFromAppDataStore()
    }

    func bumpProfileRevisionLocally() {
        profileRevision &+= 1
        objectWillChange.send()
    }

    func bumpCatalogDataRevision() {
        catalogDataRevision &+= 1
        objectWillChange.send()
        CollegePersistence.shared.applyCatalogDataRevisionBumpFromAppDataStore()
    }

    func bumpCatalogDataRevisionLocally() {
        catalogDataRevision &+= 1
        objectWillChange.send()
    }

    /// Tracks the active catalog school; all catalog rows live in the unified store.
    func setActiveCatalogSchoolID(_ schoolID: String?) throws {
        let normalized = schoolID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            activeCatalogSchoolID = nil
            return
        }
        if activeCatalogSchoolID == normalized {
            return
        }
        activeCatalogSchoolID = normalized
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
        guard activeCatalogSchoolID != nil else { return false }
        let hadChanges = profileContext.hasChanges
        guard hadChanges else { return false }
        try profileContext.save()
        bumpCatalogDataRevision()
        return true
    }

    /// Catalog data is no longer in a separate mmap'd container.
    func releaseActiveCatalogContainerForMemoryPressure() {
        activeCatalogSchoolID = nil
    }

    func useInMemoryCatalogForUnitTesting(schoolID: String = "test-school") throws {
        guard CollegeTestRuntime.isUnitTestProcess else { return }
        try setActiveCatalogSchoolID(schoolID)
    }
}
