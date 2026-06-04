// ProfileWriteRepositoryTests.swift
// Feature: Profile
// Purpose: Profile module — ProfileWriteRepositoryTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ProfileWriteRepositoryTests: PersistenceTestCase {
    private var repo: ProfileRepository { ProfileRepository(context: profileContext) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        for course in try profileContext.fetch(FetchDescriptor<PlannerCourse>()) {
            profileContext.delete(course)
        }
        for semester in try profileContext.fetch(FetchDescriptor<PlannerSemester>()) {
            profileContext.delete(semester)
        }
        for plan in try profileContext.fetch(FetchDescriptor<PlannerPlan>()) {
            profileContext.delete(plan)
        }
        for academic in try profileContext.fetch(FetchDescriptor<AcademicProfile>()) {
            profileContext.delete(academic)
        }
        for profile in try profileContext.fetch(FetchDescriptor<Profile>()) {
            profileContext.delete(profile)
        }
        try profileContext.save()
    }

    func testCreateAndDeleteSemester() throws {
        let plan = try repo.createPlan(
            name: "Write Plan",
            type: "Major",
            major: "CS",
            minor: "",
            concentration: ""
        )
        let semester = try repo.createSemester(
            plan: plan,
            name: "Spring 2027",
            year: 2027,
            season: "Spring",
            seasonOrder: repo.seasonOrder(for: "Spring")
        )

        XCTAssertEqual(try repo.fetchSemesters(limit: 10).count, 1)
        XCTAssertEqual(try repo.fetchSemester(id: semester.id)?.name, "Spring 2027")

        try repo.deleteSemester(id: semester.id)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try repo.fetchSemester(id: semester.id))
    }

    func testCreateAndDeleteCourse() throws {
        let plan = try repo.createPlan(
            name: "Course Plan",
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
            code: "MATH 201",
            name: "Calculus",
            credits: 4,
            status: "Planned",
            gradingType: "Letter Grade"
        )
        course.semester = semester
        profileContext.insert(course)
        try profileContext.save()

        XCTAssertEqual(try repo.fetchCourse(id: course.id)?.code, "MATH 201")

        try repo.deleteCourse(id: course.id)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try repo.fetchCourse(id: course.id))
    }

    func testCreatePlanPersistsFields() throws {
        let plan = try repo.createPlan(
            name: "Mirror Plan",
            type: "Minor",
            major: "Math",
            minor: "",
            concentration: ""
        )

        let mirrored = try repo.fetchPlan(id: plan.id)
        XCTAssertEqual(mirrored?.name, "Mirror Plan")
        XCTAssertEqual(mirrored?.type, "Minor")
        XCTAssertEqual(mirrored?.major, "Math")
    }

    func testUpdateSemesterDetails() throws {
        let plan = try repo.createPlan(
            name: "Update Plan",
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

        try repo.updateSemesterDetails(id: semester.id, season: "Spring", year: 2027)
        ModelMergeCoalescer.flushNow()

        let mirrored = try repo.fetchSemester(id: semester.id)
        XCTAssertEqual(mirrored?.season, "Spring")
        XCTAssertEqual(mirrored?.year, 2027)
        XCTAssertEqual(mirrored?.name, "Spring 2027")
    }

    func testProfileAndAcademicProfileWrites() throws {
        let profile = Profile(name: "Jordan Lee")
        profile.collegeName = "Example U"
        profileContext.insert(profile)

        let academic = AcademicProfile(
            sortOrder: 0,
            isPrimary: true,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        academic.gpa = 3.7
        academic.collegeName = "Example U"
        academic.profile = profile
        profileContext.insert(academic)
        try profileContext.save()

        let mirroredProfile = try repo.fetchProfile(id: profile.id)
        XCTAssertEqual(mirroredProfile?.name, "Jordan Lee")
        XCTAssertEqual(mirroredProfile?.collegeName, "Example U")
        let swiftAcademic = try repo.fetchPrimaryAcademicProfile()
        XCTAssertEqual(swiftAcademic?.gpa, 3.7)
        XCTAssertTrue(try repo.hasMirroredAcademicProfileRows())
    }

    func testPrimaryAcademicProfileFieldUpdates() throws {
        let profile = Profile(name: "Test")
        profileContext.insert(profile)
        let academic = AcademicProfile(
            sortOrder: 0,
            isPrimary: true,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        academic.collegeName = "Test U"
        academic.profile = profile
        profileContext.insert(academic)
        try profileContext.save()

        academic.classStanding = "Senior"
        academic.expectedGraduation = "May 2026"
        try profileContext.save()

        let swift = try repo.fetchPrimaryAcademicProfile()
        XCTAssertEqual(swift?.classStanding, "Senior")
        XCTAssertEqual(swift?.expectedGraduation, "May 2026")
    }

    func testReorderAcademicProfiles() throws {
        let profile = Profile(name: "Multi")
        profileContext.insert(profile)

        let first = AcademicProfile(
            sortOrder: 1,
            isPrimary: false,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        first.collegeName = "A"
        first.profile = profile

        let second = AcademicProfile(
            sortOrder: 0,
            isPrimary: true,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        second.collegeName = "B"
        second.profile = profile

        profileContext.insert(first)
        profileContext.insert(second)
        try profileContext.save()

        second.sortOrder = 0
        first.sortOrder = 1
        try profileContext.save()

        XCTAssertEqual(try repo.fetchAcademicProfile(id: second.id)?.sortOrder, 0)
        XCTAssertEqual(try repo.fetchAcademicProfile(id: first.id)?.sortOrder, 1)
    }
}
