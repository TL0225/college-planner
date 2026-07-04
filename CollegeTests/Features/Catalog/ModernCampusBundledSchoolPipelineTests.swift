// ModernCampusBundledSchoolPipelineTests.swift
// Feature: Catalog
// Purpose: Offline guarantees that every bundled Modern Campus / Acalog school can
//          traverse normalize → persist → picker read without regressions.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ModernCampusBundledSchoolPipelineTests: XCTestCase {
    private var modernCampusSchools: [SchoolManifest] {
        SchoolManifestCatalog.bundled().filter {
            CatalogParserFamily.from(declaredFormat: $0.catalogFormat) == .modernCampus
        }
    }

    override func setUp() async throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
    }

    private func clearIngestBaseline(for school: SchoolManifest) {
        let versionID = CatalogVersion.resolve(school: school, segment: .manifestOnly).id
        CatalogExtractorMetricsBaselineStore.clear(schoolID: school.id, catalogVersionID: versionID)
    }

    func testBundledModernCampusSchoolCount_isLocked() {
        XCTAssertEqual(
            modernCampusSchools.count,
            5,
            "Update this test when adding/removing bundled Modern Campus schools: \(modernCampusSchools.map(\.id))"
        )
        let ids = Set(modernCampusSchools.map(\.id))
        XCTAssertEqual(
            ids,
            Set([
                "dakota_state_university",
                "ohio_university",
                "purdue_university",
                "stony_brook",
                "university_at_buffalo",
            ])
        )
    }

    func testEveryBundledModernCampusSchool_routesThroughLiveIngestCoordinator() {
        for school in modernCampusSchools {
            XCTAssertTrue(
                CatalogBackgroundSyncRunner.supportsLiveIngestCoordinator(format: school.catalogFormat),
                school.id
            )
            XCTAssertTrue(
                SchoolManifestSelection.isScraperBacked(school),
                school.id
            )
        }
    }

    func testEveryBundledModernCampusSchool_normalizesCatalogEntryPoint() {
        let expectations: [String: (host: String, catoidHint: String?)] = [
            "dakota_state_university": ("catalog.dsu.edu", nil),
            "ohio_university": ("catalogs.ohio.edu", nil),
            "purdue_university": ("catalog.purdue.edu", nil),
            "stony_brook": ("catalog.stonybrook.edu", nil),
            "university_at_buffalo": ("catalogs.buffalo.edu", "17"),
        ]

        for school in modernCampusSchools {
            let catalogURL = school.catalogURL ?? ""
            let (normalized, hint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
            guard let expected = expectations[school.id] else {
                XCTFail("Missing normalization fixture for \(school.id)")
                continue
            }

            XCTAssertEqual(URL(string: normalized)?.host?.lowercased(), expected.host, school.id)
            XCTAssertEqual(hint, expected.catoidHint, school.id)
        }
    }

    func testEveryBundledModernCampusSchool_ingestGateAcceptsRepresentativePrograms() {
        for school in modernCampusSchools {
            clearIngestBaseline(for: school)
            let host = URL(string: school.catalogURL ?? "")?.host ?? "catalog.example.edu"
            let programs = (0..<12).map { index in
                ScrapedProgram(
                    name: "Program \(index)",
                    type: "Major",
                    url: "https://\(host)/preview_program.php?catoid=1&poid=\(index)",
                    department: "Sample Department"
                )
            }

            let outcome = CatalogIngestGate.evaluateModernCampus(
                manifest: school,
                depth: .light,
                programs: programs,
                courses: [],
                requirements: [],
                expectCourses: false
            )
            XCTAssertFalse(
                outcome.shouldAbortIngest,
                "\(school.id): \(CatalogIngestGate.abortSummary(outcome))"
            )
        }
    }

    func testEveryBundledModernCampusSchool_persistAndReadProgramsOffMain() async throws {
        for school in modernCampusSchools {
            try AppDataStore.shared.clearProfileStoreForUnitTesting()
            try AppDataStore.shared.useInMemoryCatalogForUnitTesting(schoolID: school.id)

            let repo = CatalogRepository(context: AppDataStore.shared.profileContext)
            _ = try repo.ensureUniversityForImport(
                id: UUID(),
                name: school.name,
                catalogURL: school.catalogURL ?? ""
            )
            try AppDataStore.shared.profileContext.save()

            let host = URL(string: school.catalogURL ?? "")?.host ?? "catalog.example.edu"
            let inputs: [CatalogProgramWriteBridge.ProgramInput] = [
                (
                    name: "Cyber Operations",
                    degreeLevel: "Undergraduate",
                    degreeType: "BS",
                    isMinor: false,
                    department: "Computer Science",
                    url: "https://\(host)/preview_program.php?catoid=7&poid=101",
                    resolvedDepartment: "Computer Science",
                    resolvedCollege: nil,
                    mappingConfidence: 0.9,
                    mappingSource: "test.pipeline",
                    requirements: nil,
                    trackVariant: nil,
                    parentProgramKey: nil
                ),
                (
                    name: "Data Science",
                    degreeLevel: "Graduate",
                    degreeType: "MS",
                    isMinor: false,
                    department: "Computer Science",
                    url: "https://\(host)/preview_program.php?catoid=8&poid=202",
                    resolvedDepartment: "Computer Science",
                    resolvedCollege: nil,
                    mappingConfidence: 0.9,
                    mappingSource: "test.pipeline",
                    requirements: nil,
                    trackVariant: nil,
                    parentProgramKey: nil
                ),
            ]

            try CatalogProgramWriteBridge.savePrograms(inputs, for: school.name, appDataStore: AppDataStore.shared)

            let programs = await CatalogProgramPickerBridge.selectableProgramsOffMain(
                universityNames: [school.name]
            )
            XCTAssertGreaterThanOrEqual(programs.count, 2, school.id)
            XCTAssertTrue(
                programs.contains { $0.pickerLabel.localizedCaseInsensitiveContains("Cyber Operations") },
                school.id
            )
        }
    }

    func testMergeProgramsAcrossCatalogs_dedupesByCatoidAndURL() {
        let program = ScrapedProgram(
            name: "Computer Science",
            type: "Major",
            url: "https://catalog.example.edu/preview_program.php?catoid=1&poid=10"
        )
        let merged = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs([
            (catoid: "10", programs: [program]),
            (catoid: "11", programs: [program]),
        ])
        XCTAssertEqual(merged.count, 2)

        let collapsed = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs([
            (catoid: "10", programs: [program]),
            (catoid: "10", programs: [program]),
        ])
        XCTAssertEqual(collapsed.count, 1)
    }
}
