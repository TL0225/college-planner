// AcademicsPlannerCreditsBridgeTests.swift
// Feature: Academics
// Purpose: Academics module — AcademicsPlannerCreditsBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class AcademicsPlannerCreditsBridgeTests: PersistenceTestCase {
    func testBucketsFromStoreCourses() throws {
        let plan = PlannerPlan(name: "Plan", type: "Major")
        let semester = PlannerSemester(name: "Fall 2026", year: 2026, season: "Fall")
        semester.plan = plan

        let completed = PlannerCourse(code: "CS 101", name: "Intro", credits: 3, status: "Completed", isCompleted: true)
        let inProgress = PlannerCourse(code: "CS 102", name: "Data", credits: 4, status: "In Progress")
        let planned = PlannerCourse(code: "CS 103", name: "Algo", credits: 3, status: "Planned")
        completed.semester = semester
        inProgress.semester = semester
        planned.semester = semester

        profileContext.insert(plan)
        profileContext.insert(semester)
        profileContext.insert(completed)
        profileContext.insert(inProgress)
        profileContext.insert(planned)
        try profileContext.save()

        let buckets = AcademicsPlannerCreditsBridge.buckets(from: [semester])
        XCTAssertEqual(buckets.completed, 3)
        XCTAssertEqual(buckets.inProgress, 4)
        XCTAssertEqual(buckets.planned, 3)
    }
}
