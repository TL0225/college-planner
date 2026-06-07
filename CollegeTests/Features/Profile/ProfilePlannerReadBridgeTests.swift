// ProfilePlannerReadBridgeTests.swift
// Feature: Profile
// Purpose: Profile module — ProfilePlannerReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ProfilePlannerReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let ctx = AppDataStore.shared.profileContext
        for plan in try ctx.fetch(FetchDescriptor<PlannerPlan>()) {
            ctx.delete(plan)
        }
        for profile in try ctx.fetch(FetchDescriptor<Profile>()) {
            ctx.delete(profile)
        }
        try ctx.save()
    }

    func testPlansFromStore() throws {
        let plan = PlannerPlan(name: "Swift Plan", type: "Bachelors", major: "CS", minor: "", concentration: "")
        profileContext.insert(plan)
        try profileContext.save()

        let plans = ProfilePlannerReadBridge.plans(appDataStore: AppDataStore.shared)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.name, "Swift Plan")
    }

    func testPlansEmptyWhenNoRows() throws {
        let plans = ProfilePlannerReadBridge.plans(appDataStore: AppDataStore.shared)
        XCTAssertTrue(plans.isEmpty)
    }
}
