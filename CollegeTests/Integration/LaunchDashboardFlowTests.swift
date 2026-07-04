// LaunchDashboardFlowTests.swift
// Snow Leopard flow #1: launch store opens without storeOpenError.

import XCTest
@testable import College

@MainActor
final class LaunchDashboardFlowTests: PersistenceTestCase {
    func testAppDataStoreReadyForDashboard() throws {
        XCTAssertNil(AppDataStore.shared.storeOpenError)
        _ = try PersistenceFixtureFactory.seedMinimalPlanner(in: profileContext)
        CollegePersistence.shared.refreshProfileCaches()
        XCTAssertNotNil(CollegePersistence.shared.profile)
    }
}
