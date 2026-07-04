// CatalogProgramReadBridgeTests.swift
// Feature: Catalog
// Purpose: Program label reads attach the per-school catalog store before querying.

import XCTest
import SwiftData
@testable import College

@MainActor
final class CatalogProgramReadBridgeTests: XCTestCase {
    func testFetchMajors_opensCatalogStoreAndMatchesCanonicalDegreeLevel() throws {
        let appDataStore = AppDataStore(profileContainer: try CollegeModelContainerFactory.makeProfileContainer(inMemory: true))
        try appDataStore.useInMemoryCatalogForUnitTesting(schoolID: "dakota_state_university")

        guard let repo = appDataStore.catalogRepository else {
            XCTFail("Expected in-memory catalog repository")
            return
        }

        let university = try repo.ensureUniversityForImport(
            id: UUID(),
            name: "Dakota State University",
            catalogURL: "https://catalog.dsu.edu/"
        )
        try repo.activateUniversity(id: university.id, name: university.name)
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
        try appDataStore.catalogSave()

        let labels = CatalogProgramReadBridge.fetchMajors(
            for: "Dakota State University",
            degreeLevel: "Graduate Catalog 2025-2026",
            sourceCatoid: "7",
            appDataStore: appDataStore
        )

        XCTAssertEqual(labels.count, 1)
        XCTAssertTrue(labels[0].localizedCaseInsensitiveContains("Cyber Operations"))
    }

    func testCatalogRepositoryForUniversity_readsProgramsWhenCatalogGateClosed() throws {
        let appDataStore = AppDataStore(profileContainer: try CollegeModelContainerFactory.makeProfileContainer(inMemory: true))
        XCTAssertNil(appDataStore.catalogRepository, "Catalog gate should start closed")

        let repo = CatalogRepository(context: appDataStore.profileContext)
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
        try appDataStore.profileContext.save()

        guard let (resolvedRepo, universityID) = CatalogStoreSnapshotBridge.catalogRepositoryForUniversity(
            named: "Dakota State University",
            appDataStore: appDataStore
        ) else {
            XCTFail("Expected catalog repository for seeded university")
            return
        }

        let majors = try resolvedRepo.fetchAllMajors(universityID: universityID)
        XCTAssertEqual(majors.count, 1)
        XCTAssertEqual(majors[0].name, "Cyber Operations")
    }
}
