// CatalogProgramRequirementsHydratorTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogProgramRequirementsHydratorTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

@MainActor
final class CatalogProgramRequirementsHydratorTests: XCTestCase {
    func testProgramSectionsBySchool_groupsByUniversity() {
        let dsu = CatalogProgramRequirementsHydrator.SelectableProgram(
            syncWorkItem: nil,
            pickerLabel: "Computer Science (MS)",
            sectionTitle: "Graduate > College of Computing",
            catalogLevel: "Graduate",
            universityName: "Dakota State University"
        )
        let ub = CatalogProgramRequirementsHydrator.SelectableProgram(
            syncWorkItem: nil,
            pickerLabel: "Computer Science (BS)",
            sectionTitle: "Undergraduate > School of Engineering",
            catalogLevel: "Undergraduate",
            universityName: "University at Buffalo"
        )
        let sections = CatalogProgramRequirementsHydrator.programSectionsBySchool(from: [dsu, ub])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].school, "Dakota State University")
        XCTAssertEqual(sections[1].school, "University at Buffalo")
    }

    func testProgramSectionsByPickerSection_groupsLikeOnboarding() {
        let tandon = CatalogProgramRequirementsHydrator.SelectableProgram(
            syncWorkItem: nil,
            pickerLabel: "Computer Science (BS)",
            sectionTitle: "Undergraduate > Tandon School of Engineering",
            catalogLevel: "Undergraduate",
            universityName: "New York University"
        )
        let abuDhabi = CatalogProgramRequirementsHydrator.SelectableProgram(
            syncWorkItem: nil,
            pickerLabel: "Computer Science (BS)",
            sectionTitle: "Undergraduate > NYU Abu Dhabi",
            catalogLevel: "Undergraduate",
            universityName: "New York University"
        )
        let sections = CatalogProgramRequirementsHydrator.programSectionsByPickerSection(from: [tandon, abuDhabi])
        XCTAssertEqual(sections.count, 2)
        XCTAssertTrue(sections.contains(where: { $0.title.contains("Tandon") }))
        XCTAssertTrue(sections.contains(where: { $0.title.contains("Abu Dhabi") }))
    }

    func testWorkItem_distinguishesMajorAndMinorWithSameDisplayName() {
        let major = CatalogProgramRequirementsHydrator.WorkItem(
            universityName: "Dakota State University",
            programURL: "https://catalog.example.edu/preview_program.php?catoid=1&poid=10",
            majorDisplay: "Computer Science",
            degreeType: "MS",
            isMinor: false
        )
        let minor = CatalogProgramRequirementsHydrator.WorkItem(
            universityName: "Dakota State University",
            programURL: "https://catalog.example.edu/preview_program.php?catoid=1&poid=11",
            majorDisplay: "Computer Science",
            degreeType: "Minor",
            isMinor: true
        )
        XCTAssertNotEqual(major, minor)
    }

    func testWorkItem_sameProgramDifferentDegreeTypesAreDistinct() {
        let bs = CatalogProgramRequirementsHydrator.WorkItem(
            universityName: "Test U",
            programURL: "https://catalog.example.edu/preview_program.php?poid=1",
            majorDisplay: "Computer Science, B.S.",
            degreeType: "BS",
            isMinor: false
        )
        let ms = CatalogProgramRequirementsHydrator.WorkItem(
            universityName: "Test U",
            programURL: "https://catalog.example.edu/preview_program.php?poid=2",
            majorDisplay: "Computer Science, M.S.",
            degreeType: "MS",
            isMinor: false
        )
        XCTAssertNotEqual(bs, ms)
    }
}
