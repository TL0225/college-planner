// CareerResumeIngestEnrichmentTests.swift
// Feature: Career
// Purpose: Domain and stale-skill enrichment during ingest.

import XCTest
@testable import College

final class CareerResumeIngestEnrichmentTests: XCTestCase {
    func testDetectDomainsHeuristic_findsSoftwareEngineering() async {
        let text = """
        Software Engineer with Swift, Python, and API development experience.
        Built backend services and CI/CD pipelines.
        """
        let domains = await CareerResumeIngestEnrichment.detectDomains(plainText: text)
        XCTAssertFalse(domains.isEmpty)
    }

    func testDetectStaleSkills_flagsWindows7() {
        let warnings = CareerResumeIngestEnrichment.detectStaleSkills(
            plainText: "Proficient in Windows 7 desktop support and Active Directory."
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings.contains { $0.term.lowercased().contains("windows") })
    }
}
