// PlannerCoursePersistenceFlowTests.swift
// Snow Leopard flow #2: course create → persist → reload.

import SwiftData
import XCTest
@testable import College

@MainActor
final class PlannerCoursePersistenceFlowTests: PersistenceTestCase {
    func testCoursePersistsAcrossNewContext() throws {
        let persistence = CollegePersistence.shared
        let plan = persistence.addPlan(name: "Flow Plan", type: "Bachelors", major: "CS", minor: "", concentration: "")
        let semester = persistence.addSemester(to: plan, name: "Fall 2026", year: 2026, season: "Fall")
        let course = persistence.addCourse(
            to: semester,
            code: "CSE 101",
            name: "Intro",
            credits: 3,
            status: "planned",
            gradingType: "Letter",
            professor: nil
        )
        try AppDataStore.shared.profileSave()

        let courseID = course.id
        let fresh = ModelContext(AppDataStore.shared.profileContainer)
        var descriptor = FetchDescriptor<PlannerCourse>(
            predicate: #Predicate { $0.id == courseID }
        )
        descriptor.fetchLimit = 1
        let reloaded = try fresh.fetch(descriptor).first
        XCTAssertEqual(reloaded?.code, "CSE 101")
        XCTAssertEqual(reloaded?.name, "Intro")
    }
}
