// AcademicCalendarSyncEligibilityTests.swift
// Feature: Calendar
// Purpose: Academic calendar background sync gates on active school, major, and skeleton catalog.

import SwiftData
import XCTest
@testable import College

@MainActor
final class AcademicCalendarSyncEligibilityTests: PersistenceTestCase {
    private var persistence: CollegePersistence { .shared }
    private let configsKey = "calendar.academicConfigs.v1"

    override var includesCatalog: Bool { true }

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: configsKey)
        for academic in try profileContext.fetch(FetchDescriptor<AcademicProfile>()) {
            profileContext.delete(academic)
        }
        for profile in try profileContext.fetch(FetchDescriptor<Profile>()) {
            profileContext.delete(profile)
        }
        try profileContext.save()
        persistence.refreshAll()
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: configsKey)
        try super.tearDownWithError()
    }

    func testGateRequiresActiveSchoolMajorAndSkeletonPrograms() throws {
        let schoolName = "Gate Test University"

        var gate = AcademicCalendarSyncEligibility.gate(persistence: persistence)
        XCTAssertFalse(gate.isReady)

        guard let ctx = catalogContext else {
            XCTFail("catalog context unavailable")
            return
        }
        let university = University(name: schoolName, isActive: true)
        ctx.insert(university)
        try ctx.save()
        _ = persistence.setActiveUniversity(named: schoolName)

        gate = AcademicCalendarSyncEligibility.gate(persistence: persistence)
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.activeSchoolSelected)
        XCTAssertFalse(gate.majorEntered)
        XCTAssertFalse(gate.skeletonSyncCompleted)

        let shell = try persistence.profileRepository.ensurePrimaryProfileShell()
        let academic = AcademicProfile(sortOrder: 0, isPrimary: true, isActive: true, status: AcademicProfileStatus.active.rawValue)
        academic.profile = shell
        academic.collegeName = schoolName
        academic.majorsCSV = "Computer Science"
        profileContext.insert(academic)
        try profileContext.save()
        persistence.refreshAll()

        gate = AcademicCalendarSyncEligibility.gate(persistence: persistence)
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.majorEntered)
        XCTAssertFalse(gate.skeletonSyncCompleted)

        let major = Major(name: "Computer Science", degreeLevel: DegreeConfiguration.undergraduate, isMinor: false)
        major.university = university
        ctx.insert(major)
        try ctx.save()

        gate = AcademicCalendarSyncEligibility.gate(persistence: persistence)
        XCTAssertTrue(gate.isReady)
        XCTAssertTrue(gate.skeletonSyncCompleted)
    }

    func testEligibleConfigsOnlyIncludesActiveSchoolWhenReady() throws {
        _ = persistence.setActiveUniversity(named: "Stony Brook University")

        let shell = try persistence.profileRepository.ensurePrimaryProfileShell()
        let academic = AcademicProfile(sortOrder: 0, isPrimary: true, isActive: true, status: AcademicProfileStatus.active.rawValue)
        academic.profile = shell
        academic.collegeName = "Stony Brook University"
        academic.majorsCSV = "Computer Science"
        profileContext.insert(academic)
        try profileContext.save()
        persistence.refreshAll()

        guard let ctx = catalogContext else {
            XCTFail("catalog context unavailable")
            return
        }
        let university = University(name: "Stony Brook University", isActive: true)
        ctx.insert(university)
        let major = Major(name: "Computer Science", degreeLevel: DegreeConfiguration.undergraduate, isMinor: false)
        major.university = university
        ctx.insert(major)
        try ctx.save()

        let activeConfig = AcademicCalendarConfig(
            schoolID: "stony_brook",
            name: "Stony Brook University",
            url: "https://example.edu/calendar",
            timeZoneID: "America/New_York",
            levelScope: .undergrad,
            importedScopes: [],
            departmentKey: "computer_science",
            departmentDisplayName: "Computer Science — Term Dates",
            schoolDisplayName: "Stony Brook University"
        )
        let otherConfig = AcademicCalendarConfig(
            schoolID: "other_school",
            name: "Other School",
            url: "https://other.example.edu/calendar",
            timeZoneID: "America/New_York",
            levelScope: .undergrad,
            importedScopes: [],
            departmentKey: AcademicCalendarConfig.universityWideKey,
            departmentDisplayName: "Other School Term Dates",
            schoolDisplayName: "Other School"
        )
        AcademicCalendarStore.saveAllConfigs([activeConfig, otherConfig])

        XCTAssertTrue(AcademicCalendarSyncEligibility.gate(persistence: persistence).isReady)

        let eligible = AcademicCalendarSyncEligibility.eligibleConfigs(persistence: persistence)
        XCTAssertEqual(eligible.map(\.schoolID), ["stony_brook"])
    }
}
