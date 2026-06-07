// PersistenceFixtureFactory.swift
// Feature: Shared
// Purpose: Shared module — SeedIDs.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
@testable import College

/// Seeds minimal local store rows for repository and CRUD smoke tests.
enum PersistenceFixtureFactory {
    struct SeedIDs {
        let profileID: UUID
        let planID: UUID
        let semesterID: UUID
        let courseID: UUID
        let universityID: UUID
        let catalogCourseID: UUID
    }

    @discardableResult
    static func seedMinimalPlanner(
        in context: ModelContext,
        planName: String = "Test Plan",
        semesterName: String = "Fall 2026",
        courseCode: String = "CSC 101"
    ) throws -> SeedIDs {
        let profile = Profile(name: "Test Student")
        let plan = PlannerPlan(name: planName, type: "Major")
        let semester = PlannerSemester(name: semesterName, year: 2026, season: "Fall", seasonOrder: 1)
        let course = PlannerCourse(code: courseCode, name: "Intro CS", credits: 3)

        semester.plan = plan
        course.semester = semester
        profile.academicProfiles = []

        context.insert(profile)
        context.insert(plan)
        context.insert(semester)
        context.insert(course)
        try context.save()

        return SeedIDs(
            profileID: profile.id,
            planID: plan.id,
            semesterID: semester.id,
            courseID: course.id,
            universityID: UUID(),
            catalogCourseID: UUID()
        )
    }

    @discardableResult
    static func seedMinimalCatalog(
        in context: ModelContext,
        universityName: String = "Test University",
        courseCode: String = "CSC 101",
        courseTitle: String = "Intro CS"
    ) throws -> SeedIDs {
        let university = University(name: universityName, isActive: true)
        let catalogCourse = CourseCatalog(courseCode: courseCode, title: courseTitle, credits: 3)
        catalogCourse.university = university

        context.insert(university)
        context.insert(catalogCourse)
        try context.save()

        return SeedIDs(
            profileID: UUID(),
            planID: UUID(),
            semesterID: UUID(),
            courseID: UUID(),
            universityID: university.id,
            catalogCourseID: catalogCourse.id
        )
    }
}
