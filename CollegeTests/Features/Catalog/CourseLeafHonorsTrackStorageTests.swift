// CourseLeafHonorsTrackStorageTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafHonorsTrackStorageTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Honors `index.xml` `<text>` must not overwrite baseline curriculum rows at the same program URL.
final class CourseLeafHonorsTrackStorageTests: XCTestCase {
    @MainActor
    func testProgramRequirementsStorageURL_separatesBaselineAndHonors() {
        let base = "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/"
        let manager = CollegePersistence.shared
        let baseline = manager.programRequirementsStorageURL(from: base, trackVariant: nil)
        let honors = manager.programRequirementsStorageURL(from: "\(base)#track=honors", trackVariant: "honors")
        XCTAssertNotEqual(baseline, honors)
        XCTAssertTrue(honors.contains("#track=honors"))
    }
}
