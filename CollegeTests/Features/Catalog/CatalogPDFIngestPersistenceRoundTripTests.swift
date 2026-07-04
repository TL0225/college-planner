// CatalogPDFIngestPersistenceRoundTripTests.swift
// Feature: Catalog
// Purpose: End-to-end check that parsed PDF courses/requirements persist through the real
//          import path into a throwaway in-memory catalog store and read back intact.

import XCTest
import SwiftData
@testable import College

@MainActor
final class CatalogPDFIngestPersistenceRoundTripTests: XCTestCase {
    func testParsedCoursesAndRequirementsRoundTripThroughInMemoryStore() async throws {
        // Throwaway store — never touches the real app database.
        let appDataStore = AppDataStore(
            profileContainer: try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        )
        try appDataStore.useInMemoryCatalogForUnitTesting(schoolID: "roundtrip_university")

        // 1) Parse real-format course text (descriptions + prerequisites).
        let courseText = """
        BISC 1403. Introductory Biology I. (4 Credits)
        An introduction to the principles of modern biology including cell
        structure, genetics, and evolution. Laboratory work is required.
        Prerequisites: CHEM 1101.
        BISC 2549. Genetics. (3 Credits)
        A study of the mechanisms of inheritance at the molecular, cellular,
        and population levels.
        Prerequisites: BISC 1403 or BISC 1413.
        """
        let parsedCourses = CatalogPDFCourseDescriptionParser.parse(sectionText: courseText)
        XCTAssertEqual(parsedCourses.count, 2)

        // 2) Parse requirement course tables, attributed to a known program.
        let requirementText = """
        Biological Sciences
        Major Requirements
        BISC 1403 Introductory Biology I 4
        BISC 2549 Genetics 3
        """
        let knownPrograms = [
            ScrapedProgram(
                name: "Biological Sciences",
                type: "Major",
                url: "pdf://v1/roundtrip_university/program/biological-sciences",
                degreeType: "BS"
            )
        ]
        let parsedRequirements = CatalogPDFRequirementExtractor.extractRequirements(
            sectionText: requirementText,
            knownPrograms: knownPrograms,
            courseCatalog: parsedCourses
        )
        XCTAssertFalse(parsedRequirements.isEmpty, "Expected at least one attributed requirement group")
        XCTAssertEqual(parsedRequirements.first?.major, "Biological Sciences")

        // 3) Persist through the real import service.
        let profile = SchoolProfile(
            schoolID: "roundtrip_university",
            schoolName: "Round Trip University",
            catalogURL: "https://example.edu/catalog",
            version: "1.0.0-test",
            lastUpdated: Date(),
            courses: parsedCourses,
            degreeRequirements: parsedRequirements,
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        try await CatalogSchoolImportService.importSchoolCatalog(
            profile,
            policy: .fullSnapshot,
            appDataStore: appDataStore
        )

        // 4) Read back and verify the structured data survived persistence.
        let repo = try XCTUnwrap(appDataStore.catalogRepository)
        let university = try XCTUnwrap(try repo.fetchActiveUniversity())

        let courseCount = try repo.fetchCatalogCourseCount(universityID: university.id)
        XCTAssertEqual(courseCount, 2)

        let bisc1403 = try XCTUnwrap(
            try repo.fetchCatalogCourseMatching(universityID: university.id, code: "BISC 1403")
        )
        XCTAssertEqual(bisc1403.credits, 4)
        XCTAssertNotNil(bisc1403.descriptionText, "Course description must persist")
        XCTAssertTrue(bisc1403.descriptionText?.contains("modern biology") == true)
        XCTAssertNotNil(bisc1403.prerequisiteRulesJSON, "Structured prerequisites must persist")

        let requirements = try repo.fetchDegreeRequirements(universityID: university.id)
        XCTAssertFalse(requirements.isEmpty)
        let bioRequirement = try XCTUnwrap(requirements.first { $0.major == "Biological Sciences" })
        XCTAssertEqual(bioRequirement.requirementCategory, "Major Requirements")
        XCTAssertEqual(bioRequirement.creditsRequired, 7)
        XCTAssertNotNil(bioRequirement.requiredCoursesDetailedJSON, "Requirement course details must persist")
    }
}
