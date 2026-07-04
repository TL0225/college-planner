// PDFCatalogIngestFixtureTests.swift
// Feature: Shared
// Purpose: Shared module — SchoolExpectations.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class PDFCatalogIngestFixtureTests: XCTestCase {
    private struct SchoolExpectations {
        let fixtureFilename: String
        let schoolID: String
        let minCourses: Int
        let minPrograms: Int
    }

    private let schools: [String: SchoolExpectations] = [
        "Fordham": SchoolExpectations(fixtureFilename: "fordham.pdf", schoolID: "fordham_university", minCourses: 30, minPrograms: 5),
        "CMU": SchoolExpectations(fixtureFilename: "cmu.pdf", schoolID: "carnegie_mellon_university", minCourses: 150, minPrograms: 10),
        "Brooklyn": SchoolExpectations(fixtureFilename: "brooklyn.pdf", schoolID: "brooklyn_college", minCourses: 30, minPrograms: 5),
    ]

    func testPDFPassB_courseExtraction_and_programs_areNonEmpty_fromFixtures() async throws {
        try await runAllSchools(usingFixturesOnly: true)
    }

    func testPDFPassB_courseExtraction_and_programs_fromFixtures_orIntegration_ifEnabled() async throws {
        let integrationEnabled = ProcessInfo.processInfo.environment["PDF_CATALOG_INTEGRATION"] == "1"
        if !integrationEnabled {
            throw XCTSkip("Set PDF_CATALOG_INTEGRATION=1 to run URL-based integration tests.")
        }
        try await runAllSchools(usingFixturesOnly: false)
    }

    func testProgramBlocks_rejectPolicyProsePatterns() {
        let block = CatalogPDFTextBlock(
            lines: [CatalogPDFLine(text: "The amount due must be submitted to the bursar by Step One.", pageIndex: 0, lineIndexOnPage: 0)],
            pageRange: 0...0
        )
        let classified = CatalogPDFBlockClassifier.classify(
            blocks: [block],
            sections: [],
            profile: CatalogPDFProfileLoader.profile(forSchoolID: "fordham_university")
        )
        XCTAssertNotEqual(classified.first?.type, .program)
    }

    private func runAllSchools(usingFixturesOnly: Bool) async throws {
        for (schoolKey, expectations) in schools {
            try await runOneSchool(
                schoolKey: schoolKey,
                expectations: expectations,
                usingFixturesOnly: usingFixturesOnly
            )
        }
    }

    private func runOneSchool(
        schoolKey: String,
        expectations: SchoolExpectations,
        usingFixturesOnly: Bool
    ) async throws {
        let fixturesDir = ProcessInfo.processInfo.environment["PDF_CATALOG_FIXTURES_DIR"]
        let fixtureURL = try resolveFixturePDFURL(
            fixtureFilename: expectations.fixtureFilename,
            fixturesDir: fixturesDir
        )

        if fixtureURL == nil && usingFixturesOnly {
            throw XCTSkip("Missing fixture: \(expectations.fixtureFilename) (set PDF_CATALOG_FIXTURES_DIR or add the fixture to CollegeTests).")
        }

        let pdfURL: URL
        if let url = fixtureURL {
            pdfURL = url
        } else {
            guard ProcessInfo.processInfo.environment["PDF_CATALOG_INTEGRATION"] == "1" else {
                throw XCTSkip("Integration disabled; fixture missing for \(schoolKey).")
            }
            pdfURL = try await resolveIntegrationPDFURL(forSchoolKey: schoolKey)
        }

        let output = try await CatalogPDFPipeline.run(
            pdfURL: pdfURL,
            options: CatalogPDFPipeline.Options(
                schoolID: expectations.schoolID,
                includeCourses: true,
                includePolicies: true,
                ocrFallback: true
            )
        )

        XCTAssertGreaterThan(output.foundation.pageCount, 0, "\(schoolKey): expected PDF pages")
        XCTAssertGreaterThanOrEqual(output.courses.count, expectations.minCourses, "\(schoolKey): course extraction too small")
        XCTAssertGreaterThanOrEqual(output.programs.count, expectations.minPrograms, "\(schoolKey): program extraction too small")
        for requirement in output.requirements {
            XCTAssertFalse(
                requirement.major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(schoolKey): requirement rows must be attributed to a real program"
            )
        }
        XCTAssertFalse(output.policyRows.isEmpty, "\(schoolKey): expected policy rows")

        for program in output.programs {
            XCTAssertFalse(CatalogPDFProgramRejectLexicon.hasStrongNegative(program.name), "\(schoolKey): policy-like program name: \(program.name)")
            XCTAssertLessThanOrEqual(program.name.count, 120)
        }
    }

    private func resolveFixturePDFURL(
        fixtureFilename: String,
        fixturesDir: String?
    ) throws -> URL? {
        if let fixturesDir {
            let url = URL(fileURLWithPath: fixturesDir).appendingPathComponent(fixtureFilename)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let defaultURL = repoRoot
            .appendingPathComponent("CollegeTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("PDF")
            .appendingPathComponent(fixtureFilename)
        return FileManager.default.fileExists(atPath: defaultURL.path) ? defaultURL : nil
    }

    private func resolveIntegrationPDFURL(forSchoolKey schoolKey: String) async throws -> URL {
        let manifests = SchoolManifestCatalog.bundled()
        let pdfSchools = manifests.filter { $0.catalogFormat.lowercased() == "pdf" }

        func matches(_ school: SchoolManifest, key: String) -> Bool {
            school.name.lowercased().contains(key.lowercased()) ||
            (school.shortName ?? "").lowercased().contains(key.lowercased()) ||
            school.id.lowercased().contains(key.lowercased())
        }

        let chosen = pdfSchools.first(where: { matches($0, key: schoolKey) })
        guard let manifest = chosen else {
            throw XCTSkip("No matching pdf school manifest found for \(schoolKey) in SchoolManifestCatalog (set up schools.json first).")
        }
        guard let urlString = manifest.catalogURL, let remoteURL = URL(string: urlString) else {
            throw XCTSkip("Matched \(schoolKey), but manifest.catalog_url is missing/invalid.")
        }

        let (localURL, _) = try await URLSession.shared.download(from: remoteURL)
        return localURL
    }
}
