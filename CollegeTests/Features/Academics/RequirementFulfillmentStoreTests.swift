// RequirementFulfillmentStoreTests.swift
// Feature: Academics
// Purpose: Academics module — RequirementFulfillmentStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class RequirementFulfillmentStoreTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    func testAssignAndFetch() throws {
        guard let catalogContext else {
            XCTFail("missing catalog context")
            return
        }
        try RequirementFulfillmentStore.assign(
            context: catalogContext,
            university: "New York University",
            programURL: "https://example.edu/program",
            requirementCategory: "General Education Requirements — Foreign Language",
            courseCode: "SPAN-UA 1"
        )

        let rows = RequirementFulfillmentStore.assignments(
            context: catalogContext,
            university: "New York University",
            programURL: "https://example.edu/program",
            requirementCategory: "General Education Requirements — Foreign Language"
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.courseCode.uppercased(), "SPAN-UA 1")
    }

    func testRemoveAssignment() throws {
        guard let catalogContext else {
            XCTFail("missing catalog context")
            return
        }
        try RequirementFulfillmentStore.assign(
            context: catalogContext,
            university: "New York University",
            programURL: "https://example.edu/program",
            requirementCategory: "Electives — Other Elective Credits",
            courseCode: "ECON-UA 1"
        )
        try RequirementFulfillmentStore.remove(
            context: catalogContext,
            university: "New York University",
            programURL: "https://example.edu/program",
            requirementCategory: "Electives — Other Elective Credits",
            courseCode: "ECON-UA 1"
        )
        let rows = RequirementFulfillmentStore.assignments(
            context: catalogContext,
            university: "New York University",
            programURL: "https://example.edu/program",
            requirementCategory: "Electives — Other Elective Credits"
        )
        XCTAssertTrue(rows.isEmpty)
    }
}
