// AcademicsAuditSnapshotStoreTests.swift
// Feature: Academics
// Purpose: Academics module — AcademicsAuditSnapshotStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class AcademicsAuditSnapshotStoreTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    private let universityName = "Audit Snapshot U"
    private let programURL = "https://example.edu/catalog/cs-bs"
    private let majorName = "Computer Science"

    private func activateCatalogUniversity(_ university: University) throws {
        let catalogContext = try XCTUnwrap(catalogContext)
        let repo = CatalogRepository(context: catalogContext)
        try repo.activateUniversity(id: university.id, name: universityName)
        try catalogContext.save()
        CollegePersistence.shared.refreshAll()
    }

    func testBatchCatalogLookup_resolvesCourseTitleAndCredits() async throws {
        let catalogContext = try XCTUnwrap(catalogContext)
        let university = University(name: universityName, isActive: false)
        let course = CourseCatalog(courseCode: "CSE 101", title: "Intro to CS", credits: 4, isHydrated: true)
        course.university = university
        catalogContext.insert(university)
        catalogContext.insert(course)
        try catalogContext.save()
        try activateCatalogUniversity(university)

        let snapshots = await AuditCatalogLookupBridge.batchMatchingOffMain(
            universityID: university.id,
            codes: ["CSE 101"]
        )
        XCTAssertEqual(snapshots["CSE 101"]?.title, "Intro to CS")
        XCTAssertEqual(snapshots["CSE 101"]?.creditsDisplayText, "4")
    }

    func testReloadAudit_buildsDegreeWithBatchCatalogMetadata() async throws {
        let catalogContext = try XCTUnwrap(catalogContext)
        let university = University(name: universityName, isActive: true)
        let major = Major(name: majorName, degreeLevel: "Undergraduate", isMinor: false)
        major.degreeType = "BS"
        major.university = university

        let course = CourseCatalog(courseCode: "CSE 101", title: "Intro to CS", credits: 4, isHydrated: true)
        course.university = university

        let requirement = CatalogDegreeRequirement(
            degreeType: "BS",
            major: majorName,
            requirementCategory: "Core",
            sectionOrder: 0,
            creditsRequired: 4
        )
        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        major.programURL = canonicalURL
        requirement.programURL = canonicalURL
        requirement.requiredCourses = "CSE 101"
        requirement.university = university

        catalogContext.insert(university)
        catalogContext.insert(major)
        catalogContext.insert(course)
        catalogContext.insert(requirement)
        try catalogContext.save()
        try activateCatalogUniversity(university)

        let profile = Profile(name: "Audit Student")
        let academic = AcademicProfile(
            sortOrder: 0,
            isPrimary: true,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue
        )
        academic.profile = profile
        academic.degreeType = "BS"
        academic.degreeLevel = "Undergraduate"
        AcademicProfileProgramLists.syncToProfile(majors: [majorName], minors: [], profile: academic)
        profileContext.insert(profile)
        profileContext.insert(academic)
        try profileContext.save()
        CollegePersistence.shared.refreshAll()

        let store = AuditSnapshotStore()
        _ = await store.reloadAudit(
            collegePersistence: .shared,
            majors: [majorName],
            minors: [],
            academicProfile: academic
        )

        XCTAssertFalse(store.isLoadingAudit)
        XCTAssertEqual(store.auditDegrees.count, 1)
        let items = store.auditDegrees.first?.categories.first?.items ?? []
        XCTAssertEqual(items.first?.code, "CSE 101")
        XCTAssertEqual(items.first?.title, "Intro to CS")
        XCTAssertEqual(items.first?.credits, "4")
    }
}
