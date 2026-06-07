// CourseLeafCatalogCatoidMatchingTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafCatalogCatoidMatchingTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafCatalogCatoidMatchingTests: XCTestCase {
    func testPathPrefixes_nyuUndergraduate() {
        let prefixes = CourseLeafCatalogSegmentDiscoverer.pathPrefixes(
            forCatalogID: "new_york_university_undergraduate"
        )
        XCTAssertEqual(prefixes, ["/undergraduate/"])
    }

    @MainActor
    func testOnboardingProgramIndexLooksComplete_requiresBroadCoverage() {
        XCTAssertFalse(
            CourseLeafCatalogIngestAdapter.onboardingProgramIndexLooksComplete(
                presence: (courses: 0, departments: 0, majors: 12, minors: 0)
            )
        )
        XCTAssertTrue(
            CourseLeafCatalogIngestAdapter.onboardingProgramIndexLooksComplete(
                presence: (courses: 0, departments: 8, majors: 180, minors: 40)
            )
        )
    }

    func testProgramURLMatchesCatalogID_nyuPaths() {
        let programURL = "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology-ba/"
        XCTAssertTrue(
            CourseLeafCatalogSegmentDiscoverer.programURLMatchesCatalogID(
                programURL,
                catalogID: "new_york_university_undergraduate"
            )
        )
        XCTAssertFalse(
            CourseLeafCatalogSegmentDiscoverer.programURLMatchesCatalogID(
                programURL,
                catalogID: "new_york_university_graduate"
            )
        )
    }

    @MainActor
    func testSaveAndFetchMajors_persistsCourseLeafCatalogProvenance() throws {
        throw XCTSkip("Rewritten for local store CatalogProgramWriteBridge in Phase 7f follow-up.")
    }

    @MainActor
    func testSaveAndFetchMajors_engineeringComputerScienceBucketsUnderTandon() throws {
        throw XCTSkip("Rewritten for local store CatalogProgramWriteBridge in Phase 7f follow-up.")
    }
}
