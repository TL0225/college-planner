// CatalogProgramPickerBridgeTests.swift
// Feature: Catalog
// Purpose: Off-main requirements picker resolves universities case-insensitively.

import XCTest
import SwiftData
@testable import College

@MainActor
final class CatalogProgramPickerBridgeTests: XCTestCase {
    override func setUp() async throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
    }

    func testSelectableProgramsOffMain_returnsProgramsWhenUniversityNameCasingDiffers() async throws {
        let repo = CatalogRepository(context: AppDataStore.shared.profileContext)
        let university = try repo.ensureUniversityForImport(
            id: UUID(),
            name: "Dakota State University",
            catalogURL: "https://catalog.dsu.edu/"
        )
        try repo.upsertMajors(
            universityID: university.id,
            inputs: [
                CatalogRepository.MajorUpsertInput(
                    id: UUID(),
                    name: "Cyber Operations",
                    degreeLevel: "Graduate",
                    degreeType: "MS",
                    isMinor: false,
                    programURL: "https://catalog.dsu.edu/preview_program.php?catoid=7&poid=123",
                    programURLs: nil,
                    sourceCatoids: "7",
                    resolvedDepartment: "Computer Science",
                    resolvedCollege: nil,
                    departmentIDs: [],
                    catalogStableID: nil,
                    provenanceJSON: nil,
                    mappingConfidence: nil,
                    mappingSource: "test",
                    parserVersion: "test",
                    programKind: nil,
                    parentProgramKey: nil,
                    trackVariant: nil,
                    catalogEditionID: nil
                ),
            ]
        )
        try AppDataStore.shared.profileContext.save()

        let programs = await CatalogProgramPickerBridge.selectableProgramsOffMain(
            universityNames: ["dakota state university"]
        )

        XCTAssertEqual(programs.count, 1)
        XCTAssertTrue(programs[0].pickerLabel.localizedCaseInsensitiveContains("Cyber Operations"))
        XCTAssertEqual(programs[0].universityName, "Dakota State University")
    }

    func testSelectableProgramsOffMain_returnsProgramsWhenCatalogGateClosed() async throws {
        XCTAssertNil(AppDataStore.shared.catalogRepository, "Catalog gate should start closed")

        let repo = CatalogRepository(context: AppDataStore.shared.profileContext)
        let university = try repo.ensureUniversityForImport(
            id: UUID(),
            name: "Dakota State University",
            catalogURL: "https://catalog.dsu.edu/"
        )
        try repo.upsertMajors(
            universityID: university.id,
            inputs: [
                CatalogRepository.MajorUpsertInput(
                    id: UUID(),
                    name: "Computer Science",
                    degreeLevel: "Undergraduate",
                    degreeType: "BS",
                    isMinor: false,
                    programURL: nil,
                    programURLs: nil,
                    sourceCatoids: nil,
                    resolvedDepartment: nil,
                    resolvedCollege: nil,
                    departmentIDs: [],
                    catalogStableID: nil,
                    provenanceJSON: nil,
                    mappingConfidence: nil,
                    mappingSource: "test",
                    parserVersion: "test",
                    programKind: nil,
                    parentProgramKey: nil,
                    trackVariant: nil,
                    catalogEditionID: nil
                ),
            ]
        )
        try AppDataStore.shared.profileContext.save()

        let programs = await CatalogProgramPickerBridge.selectableProgramsOffMain(
            universityNames: ["Dakota State University"]
        )

        XCTAssertEqual(programs.count, 1)
        XCTAssertTrue(programs[0].pickerLabel.localizedCaseInsensitiveContains("Computer Science"))
    }
}
