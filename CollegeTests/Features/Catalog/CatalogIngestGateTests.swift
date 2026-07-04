// CatalogIngestGateTests.swift
// Feature: Shared
// Purpose: Catalog platform PR0 gate — invariants, sanity, recovery, review severity.

import XCTest
@testable import College

final class CatalogIngestGateTests: XCTestCase {
    private func makeManifest(id: String = "test_school") -> SchoolManifest {
        SchoolManifest(
            id: id,
            name: "Test School",
            shortName: "Test",
            unitID: nil,
            opeID: nil,
            profileURL: "https://example.edu/profile.json",
            catalogURL: "https://bulletin.example.edu/",
            academicCalendarURL: nil,
            timeZoneID: nil,
            countryCode: "US",
            stateCode: "NY",
            officialWebsiteURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: "courseleaf",
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
    }

    func testReviewSeverity_onlyCriticalBlocksIngest() {
        XCTAssertTrue(CatalogReviewSeverity.critical.blocksIngest)
        XCTAssertFalse(CatalogReviewSeverity.warning.blocksIngest)
        XCTAssertFalse(CatalogReviewSeverity.informational.blocksIngest)
    }

    func testStructuralInvariant_failsWhenNoProgramsExpected() {
        let result = CatalogStructuralInvariantValidator.validate(
            .init(
                expectPrograms: true,
                expectCourses: false,
                expectRequirements: false,
                programsFound: 0,
                coursesFound: 10,
                requirementsFound: 0,
                orphanRequirementCount: 0
            )
        )
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failedScopes.contains(.programs))
    }

    func testIngestGate_passesWithProgramsAndCourses() {
        let program = ScrapedProgram(
            name: "Computer Science BS",
            type: "Major",
            url: "https://bulletin.example.edu/undergraduate/computer-science/",
            department: "CSE",
            college: "Engineering",
            degreeType: "BS"
        )
        let course = CatalogCourse(
            courseCode: "CSE 115",
            title: "Intro",
            credits: 3,
            department: "CSE"
        )
        let outcome = CatalogIngestGate.evaluateCourseLeaf(
            manifest: makeManifest(),
            depth: .light,
            programs: [program],
            courses: [course],
            requirements: []
        )
        XCTAssertFalse(outcome.shouldAbortIngest)
        XCTAssertEqual(outcome.recovery.outcome, .pass)
    }

    func testRecovery_partialWhenRequirementsScopeSoftFails() {
        let metrics = CatalogIngestRecoveryPolicy.Metrics(
            programsFound: 50,
            coursesFound: 200,
            requirementsFound: 0
        )
        let invariants = CatalogIngestRecoveryPolicy.InvariantResult(passed: true)
        let decision = CatalogIngestRecoveryPolicy.evaluate(
            metrics: metrics,
            invariantResult: invariants,
            severity: .informational
        )
        XCTAssertEqual(decision.outcome, .partial)
        XCTAssertTrue(decision.blockedScopes.contains(.requirements))
        XCTAssertTrue(decision.allowedScopes.contains(.programs))
    }
}
