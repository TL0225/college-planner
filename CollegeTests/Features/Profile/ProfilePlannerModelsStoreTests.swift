// ProfilePlannerModelsStoreTests.swift
// Feature: Profile
// Purpose: Profile module — ProfilePlannerModelsStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class ProfilePlannerModelsStoreTests: PersistenceTestCase {
    func testCreateReadUpdateDeleteSemesterPlanCourse() throws {
        let ids = try PersistenceFixtureFactory.seedMinimalPlanner(in: profileContext)
        let repository = ProfileRepository(context: profileContext)

        let plans = try repository.fetchPlans(limit: 10)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.id, ids.planID)

        let semesters = try repository.fetchSemesters(limit: 10)
        XCTAssertEqual(semesters.count, 1)
        XCTAssertEqual(semesters.first?.id, ids.semesterID)

        let courses = try repository.fetchCourses(forSemesterID: ids.semesterID, limit: 10)
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.id, ids.courseID)

        guard let semester = try repository.fetchSemester(id: ids.semesterID) else {
            return XCTFail("Missing semester")
        }
        semester.name = "Spring 2027"
        semester.year = 2027
        try profileContext.save()

        let updated = try repository.fetchSemester(id: ids.semesterID)
        XCTAssertEqual(updated?.name, "Spring 2027")
        XCTAssertEqual(updated?.year, 2027)

        if let course = try repository.fetchCourse(id: ids.courseID) {
            profileContext.delete(course)
        }
        if let plan = try repository.fetchPlan(id: ids.planID) {
            profileContext.delete(semester)
            profileContext.delete(plan)
        }
        try profileContext.save()

        XCTAssertTrue(try repository.fetchPlans(limit: 10).isEmpty)
        XCTAssertTrue(try repository.fetchSemesters(limit: 10).isEmpty)
    }

    func testAppDataStoreRepositoryAccessors() throws {
        let store = try PersistenceTestHarness.makeAppDataStore()
        _ = try PersistenceFixtureFactory.seedMinimalPlanner(in: store.profileContext)
        XCTAssertEqual(try store.profileRepository.fetchPlans(limit: 5).count, 1)
        XCTAssertNil(store.catalogRepository)
    }
}
