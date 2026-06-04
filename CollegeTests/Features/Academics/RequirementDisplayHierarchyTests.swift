// RequirementDisplayHierarchyTests.swift
// Feature: Academics
// Purpose: Academics module — RequirementDisplayHierarchyTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class RequirementDisplayHierarchyTests: XCTestCase {
    func testGenEdDistributionBucketIsSectionPlusRow() {
        let h = RequirementRowNormalizer.displayHierarchy(
            categoryPath: "General Education Requirements — Foreign Language",
            displayTitle: "Foreign Language",
            rowKind: .distributionBucket
        )
        XCTAssertEqual(h.sectionHeader, "General Education Requirements")
        XCTAssertEqual(h.rowTitle, "Foreign Language")
    }

    func testMajorCourseListTitleOnCategoryRow() {
        let h = RequirementRowNormalizer.displayHierarchy(
            categoryPath: "Major Requirements — Computer Science Courses",
            displayTitle: "Computer Science Courses",
            rowKind: .courseList
        )
        XCTAssertEqual(h.sectionHeader, "Major Requirements")
        XCTAssertEqual(h.rowTitle, "Computer Science Courses")
    }

    func testChooseOneUnderMathUsesLeafRowTitle() {
        let h = RequirementRowNormalizer.displayHierarchy(
            categoryPath: "Major Requirements — Mathematics Courses — Select one of the following",
            displayTitle: "Select one of the following",
            rowKind: .chooseOne
        )
        XCTAssertEqual(h.sectionHeader, "Major Requirements")
        XCTAssertEqual(h.rowTitle, "Select one of the following")
    }

    func testElectiveRuleRowUsesLeafTitle() {
        let h = RequirementRowNormalizer.displayHierarchy(
            categoryPath: "Electives — Select five elective credits from courses numbered CSCI-UA 4XX",
            displayTitle: "Select five elective credits from courses numbered CSCI-UA 4XX",
            rowKind: .ruleBucket
        )
        XCTAssertEqual(h.sectionHeader, "Electives")
        XCTAssertEqual(
            h.rowTitle,
            "Select five elective credits from courses numbered CSCI-UA 4XX"
        )
    }
}
