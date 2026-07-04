// CatalogModelsStoreTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogModelsStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

final class CatalogModelsStoreTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    func testUniversityCourseCatalogRoundTrip() throws {
        let catalogContext = try XCTUnwrap(catalogContext)
        let uniID = UUID()
        let courseID = UUID()

        let uni = University(id: uniID, name: "Test U", isActive: true)
        uni.shortName = "TU"
        uni.catalogURL = "https://example.edu/catalog"
        let dept = Department(id: UUID(), name: "Computer Science")
        dept.code = "CSE"
        dept.school = "Engineering"
        dept.university = uni
        uni.departments = [dept]

        let course = CourseCatalog(
            id: courseID,
            courseCode: "CSE 101",
            title: "Intro CS",
            credits: 3,
            isHydrated: true,
            isArchived: false
        )
        course.university = uni
        course.departmentEntity = dept
        uni.courses = [course]

        catalogContext.insert(uni)
        try catalogContext.save()

        let fetched = try catalogContext.fetch(
            FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { $0.id == courseID }
            )
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.courseCode, "CSE 101")
        XCTAssertEqual(fetched.first?.university?.name, "Test U")
    }

    func testDegreeRequirementInsert() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(id: UUID(), name: "Test U", isActive: true)
        ctx.insert(uni)
        let req = CatalogDegreeRequirement(
            id: UUID(),
            degreeType: "BS",
            major: "Computer Science",
            requirementCategory: "Core",
            sectionOrder: 0,
            creditsRequired: 12
        )
        req.university = uni
        try ctx.save()

        let count = try ctx.fetchCount(FetchDescriptor<CatalogDegreeRequirement>())
        XCTAssertEqual(count, 1)
    }

    func testCatalogRepositoryUpsertDepartmentsAndMajors() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(name: "Mirror U", isActive: true)
        ctx.insert(uni)
        try ctx.save()

        let repo = CatalogRepository(context: ctx)
        let departmentID = UUID()
        try repo.upsertDepartments(
            universityID: uni.id,
            inputs: [
                CatalogRepository.DepartmentUpsertInput(
                    id: departmentID,
                    name: "Computer Science",
                    code: "CSE",
                    school: "Engineering",
                    extractionConfidence: nil,
                    signalSource: nil,
                    parserVersion: nil
                )
            ]
        )
        let programID = UUID()
        try repo.upsertMajors(
            universityID: uni.id,
            inputs: [
                CatalogRepository.MajorUpsertInput(
                    id: programID,
                    name: "Computer Science",
                    degreeLevel: "Undergraduate",
                    degreeType: "BS",
                    isMinor: false,
                    programURL: "https://bulletins.example.edu/programs/cs-bs",
                    programURLs: nil,
                    sourceCatoids: "12345",
                    resolvedDepartment: "Computer Science",
                    resolvedCollege: "Engineering",
                    departmentIDs: [departmentID],
                    catalogStableID: nil,
                    provenanceJSON: nil,
                    mappingConfidence: nil,
                    mappingSource: nil,
                    parserVersion: nil,
                    programKind: nil,
                    parentProgramKey: nil,
                    trackVariant: nil,
                    catalogEditionID: nil
                )
            ]
        )

        let majors = try repo.fetchMajors(universityID: uni.id, limit: 10)
        XCTAssertEqual(majors.count, 1)
        XCTAssertEqual(majors.first?.id, programID)
        XCTAssertEqual(majors.first?.departments?.first?.name, "Computer Science")
    }

    func testCatalogRepositoryPagedFetch() throws {
        let ctx = try XCTUnwrap(catalogContext)
        let uni = University(name: "Paged U", isActive: true)
        ctx.insert(uni)
        for index in 0..<5 {
            let course = CourseCatalog(courseCode: "CSE \(100 + index)", title: "Course \(index)", credits: 3)
            course.university = uni
            ctx.insert(course)
        }
        try ctx.save()

        let repo = CatalogRepository(context: ctx)
        let page = try repo.fetchCatalogCoursesPage(universityID: uni.id, offset: 0, limit: 2)
        XCTAssertEqual(page.count, 2)
    }
}
