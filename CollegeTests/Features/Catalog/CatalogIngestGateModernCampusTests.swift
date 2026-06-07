// CatalogIngestGateModernCampusTests.swift
// Feature: Catalog
// Purpose: Modern Campus ingest gate — invariants, recovery, layout profile metrics.

import XCTest
@testable import College

final class CatalogIngestGateModernCampusTests: XCTestCase {
    private func makeManifest() -> SchoolManifest {
        SchoolManifest(
            id: "university_at_buffalo",
            name: "University at Buffalo",
            shortName: "UB",
            unitID: nil,
            opeID: nil,
            profileURL: "https://www.buffalo.edu/profile.json",
            catalogURL: "https://catalogs.buffalo.edu/",
            countryCode: "US",
            stateCode: "NY",
            officialWebsiteURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: "moderncampus",
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
    }

    func testEvaluateModernCampus_passesWithPrograms() {
        let program = ScrapedProgram(
            name: "Computer Science BS",
            type: "Major",
            url: "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=1",
            department: "CSE",
            college: "Engineering"
        )
        let outcome = CatalogIngestGate.evaluateModernCampus(
            manifest: makeManifest(),
            depth: .light,
            programs: [program],
            courses: [],
            requirements: [],
            layoutProfileID: "sidebarN2Links"
        )
        XCTAssertFalse(outcome.shouldAbortIngest)
        XCTAssertEqual(outcome.metrics.source, "moderncampus")
        XCTAssertEqual(outcome.metrics.layoutProfileID, "sidebarN2Links")
        XCTAssertEqual(outcome.recovery.outcome, .pass)
    }

    func testEvaluateModernCampus_criticalWhenNoPrograms() {
        let outcome = CatalogIngestGate.evaluateModernCampus(
            manifest: makeManifest(),
            depth: .light,
            programs: [],
            courses: [],
            requirements: [],
            layoutProfileID: "entityPreviewProgram"
        )
        XCTAssertTrue(outcome.reviewSeverity == .critical || outcome.shouldAbortIngest)
    }

    func testEvaluateModernCampus_partialBlocksRequirementsOnSoftFailure() {
        let metrics = CatalogIngestRecoveryPolicy.Metrics(
            programsFound: 40,
            coursesFound: 0,
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

        let gate = CatalogIngestGate.evaluateModernCampus(
            manifest: makeManifest(),
            depth: .full,
            programs: (0..<40).map { i in
                ScrapedProgram(
                    name: "Program \(i)",
                    type: "Major",
                    url: "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=\(i)"
                )
            },
            courses: [
                CatalogCourse(courseCode: "CSE 115", title: "Intro", credits: 3, department: "CSE")
            ],
            requirements: [],
            layoutProfileID: "blockN2Table"
        )
        XCTAssertFalse(gate.allowsRequirements)
    }
}
