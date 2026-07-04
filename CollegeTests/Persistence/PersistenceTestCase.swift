// PersistenceTestCase.swift
// Feature: Shared
// Purpose: Shared module — PersistenceTestCase.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

/// Base test case using the shared in-memory local store store (same context as production bridges).
@MainActor
class PersistenceTestCase: XCTestCase {
    private(set) var harness: PersistenceTestHarness.Containers!
    private(set) var profileContext: ModelContext!
    private(set) var catalogContext: ModelContext?

    var includesCatalog: Bool { false }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let store = AppDataStore.shared
        try store.clearProfileStoreForUnitTesting()
        profileContext = store.profileContext
        if includesCatalog {
            try store.useInMemoryCatalogForUnitTesting()
            catalogContext = store.profileContext
        } else {
            store.releaseActiveCatalogContainerForMemoryPressure()
            catalogContext = nil
        }
        harness = PersistenceTestHarness.Containers(
            profile: store.profileContainer,
            catalog: includesCatalog ? store.profileContainer : nil
        )
        CollegePersistence.shared.refreshAll()
    }

    override func tearDownWithError() throws {
        harness = nil
        profileContext = nil
        catalogContext = nil
        try super.tearDownWithError()
    }
}
