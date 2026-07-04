// ModernCampusProgramPersistenceTests.swift
// Feature: Catalog
// Purpose: Regression coverage for ModernCampus skeleton persistence — degreeType
//          inference for IR-extracted programs and tolerant degree-level matching.
// Data: Pure value-level helpers (no SwiftData store required).

import XCTest
@testable import College

@MainActor
final class ModernCampusProgramPersistenceTests: XCTestCase {
    // MARK: - degreeType inference (buildMajorRows)

    /// IR-extracted programs (`mappingSource …ir|entityPreviewProgram`) arrive with
    /// `type == "Program"` and `degreeType == nil`. The save path must recover the
    /// degree token from the program's display name so requirement hydration and
    /// profile link resolution can match it.
    func testBuildMajorRows_infersDegreeTypeFromNameForIRProgram() {
        let program = ScrapedProgram(
            name: "Cyber Defense, M.S.",
            type: "Program",
            url: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )

        let rows = CatalogBackgroundSyncRunner.buildMajorRows(
            from: [program],
            extractedRequirements: [],
            mappingSource: "test.moderncampus.ir|entityPreviewProgram",
            degreeLevelForProgram: { _ in "Graduate" }
        )

        XCTAssertEqual(rows.first?.degreeType, "MS")
        XCTAssertEqual(rows.first?.degreeLevel, "Graduate")
        XCTAssertEqual(rows.first?.isMinor, false)
    }

    /// When the catalog bucket can't be normalized to a real level (e.g. "Catalog 45"),
    /// fall back to the level implied by the program name.
    func testBuildMajorRows_fallsBackDegreeLevelToNameInference() {
        let program = ScrapedProgram(
            name: "Cyber Defense, M.S.",
            type: "Program",
            url: "https://catalog.dsu.edu/preview_program.php?catoid=45&poid=3975"
        )

        let rows = CatalogBackgroundSyncRunner.buildMajorRows(
            from: [program],
            extractedRequirements: [],
            mappingSource: "test",
            degreeLevelForProgram: { _ in "Catalog 45" }
        )

        XCTAssertEqual(rows.first?.degreeLevel, "Graduate")
        XCTAssertEqual(rows.first?.degreeType, "MS")
    }

    /// An explicit degreeType from the scraper is normalized and always wins over name inference.
    func testBuildMajorRows_preservesAndNormalizesExplicitDegreeType() {
        let program = ScrapedProgram(
            name: "Computer Science",
            type: "Major",
            url: "https://catalog.dsu.edu/preview_program.php?catoid=44&poid=3748",
            degreeType: "B.S."
        )

        let rows = CatalogBackgroundSyncRunner.buildMajorRows(
            from: [program],
            extractedRequirements: [],
            mappingSource: "test",
            degreeLevelForProgram: { _ in "Undergraduate" }
        )

        XCTAssertEqual(rows.first?.degreeType, "BS")
        XCTAssertEqual(rows.first?.degreeLevel, "Undergraduate")
    }

    /// A name without a degree suffix should not invent a degreeType.
    func testBuildMajorRows_leavesDegreeTypeNilWhenNoSuffix() {
        let program = ScrapedProgram(
            name: "Liberal Arts",
            type: "Program",
            url: "https://catalog.dsu.edu/preview_program.php?catoid=44&poid=9999"
        )

        let rows = CatalogBackgroundSyncRunner.buildMajorRows(
            from: [program],
            extractedRequirements: [],
            mappingSource: "test",
            degreeLevelForProgram: { _ in "Undergraduate" }
        )

        XCTAssertNil(rows.first?.degreeType)
        XCTAssertEqual(rows.first?.degreeLevel, "Undergraduate")
    }

    // MARK: - tolerant degree-level matching (resolveProgramURL)

    func testDegreeLevelsMatch_treatsCatalogTitleAsCanonicalLevel() {
        XCTAssertTrue(
            CatalogRepository.degreeLevelsMatch(stored: "Graduate Catalog 2025-2026", requested: "Graduate")
        )
        XCTAssertTrue(
            CatalogRepository.degreeLevelsMatch(stored: "Undergraduate Catalog 2024-2025", requested: "Undergraduate")
        )
        XCTAssertTrue(
            CatalogRepository.degreeLevelsMatch(stored: "Graduate", requested: "Graduate")
        )
    }

    func testDegreeLevelsMatch_rejectsCrossLevel() {
        XCTAssertFalse(
            CatalogRepository.degreeLevelsMatch(stored: "Undergraduate Catalog 2025-2026", requested: "Graduate")
        )
        XCTAssertFalse(
            CatalogRepository.degreeLevelsMatch(stored: "Graduate", requested: "Undergraduate")
        )
    }

    func testDegreeLevelsMatch_emptyRequestedAlwaysMatches() {
        XCTAssertTrue(CatalogRepository.degreeLevelsMatch(stored: "Graduate Catalog 2025-2026", requested: ""))
        XCTAssertTrue(CatalogRepository.degreeLevelsMatch(stored: "", requested: "   "))
    }
}
