// ProfilePlannerSyncBridgeTests.swift
// Feature: Profile
// Purpose: Profile module — ProfilePlannerSyncBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ProfilePlannerSyncBridgeTests: PersistenceTestCase {
    func testPlannerSnapshotRoundTripInStore() throws {
        let repo = ProfileRepository(context: profileContext)
        let plan = try repo.createPlan(
            name: "Sync Plan",
            type: "Major",
            major: "CS",
            minor: "",
            concentration: ""
        )
        let semester = try repo.createSemester(
            plan: plan,
            name: "Fall 2026",
            year: 2026,
            season: "Fall",
            seasonOrder: repo.seasonOrder(for: "Fall")
        )
        let course = PlannerCourse(
            code: "CS 101",
            name: "Intro",
            credits: 3,
            status: "Planned",
            gradingType: "Letter Grade"
        )
        course.semester = semester
        profileContext.insert(course)
        try profileContext.save()

        XCTAssertEqual(try repo.fetchPlans(limit: 5).count, 1)
        XCTAssertEqual(try repo.fetchSemesters(limit: 5).count, 1)
        XCTAssertEqual(try repo.totalPlannerCourseCount(), 1)
    }

    func testDeleteSemesterRemovesStoreRow() throws {
        let repo = ProfileRepository(context: profileContext)
        let plan = try repo.createPlan(
            name: "Plan A",
            type: "Major",
            major: "CS",
            minor: "",
            concentration: ""
        )
        let semester = try repo.createSemester(
            plan: plan,
            name: "Fall 2026",
            year: 2026,
            season: "Fall",
            seasonOrder: repo.seasonOrder(for: "Fall")
        )
        XCTAssertEqual(try repo.fetchSemesters(limit: 5).count, 1)

        try repo.deleteSemester(id: semester.id)
        ModelMergeCoalescer.flushNow()
        XCTAssertTrue(try repo.fetchSemesters(limit: 5).isEmpty)
    }
}
