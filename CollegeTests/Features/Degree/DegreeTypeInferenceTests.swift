// DegreeTypeInferenceTests.swift
// Feature: Degree
// Purpose: Degree module — DegreeTypeInferenceTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class DegreeTypeInferenceTests: XCTestCase {

    func testNormalizeParentheticalMS() {
        let result = DegreeTypeNormalizer.normalize("Cyber Defense (M.S.)")
        XCTAssertEqual(result?.token, "MS")
        XCTAssertEqual(result?.degreeLevel, DegreeConfiguration.graduate)
        XCTAssertTrue(result?.isConfirmed == true)
    }

    func testNormalizeTrailingPeriodDottedMS() {
        let tokens = CatalogDegreeTypeFilter.strictFilterTokens(forPickerValue: "Cyber Defense M.S.")
        XCTAssertTrue(tokens.contains("MS"))
        let inferred = DeclaredProgramDegreeMetadata.infer(fromProgramDisplay: "Cyber Defense M.S.")
        XCTAssertEqual(inferred?.token, "MS")
    }

    func testNormalizeFirstWordPrefixForm() {
        let result = DegreeTypeNormalizer.normalize("M.S. in Computer Science")
        XCTAssertEqual(result?.token, "MS")
    }

    func testNormalizeSpelledOutPhrase() {
        let result = DegreeTypeNormalizer.normalize("Master of Science in Cybersecurity")
        XCTAssertEqual(result?.token, "MS")
        XCTAssertEqual(result?.fullLabel, "Master of Science (MS)")
    }

    func testIdempotentCanonicalLabel() {
        let input = "Master of Science (MS)"
        let a = DegreeTypeNormalizer.normalize(input)
        let b = DegreeTypeNormalizer.normalize(a?.fullLabel ?? input)
        XCTAssertEqual(a?.token, b?.token)
        XCTAssertEqual(a?.fullLabel, b?.fullLabel)
    }

    func testShouldUpdateWhenStaleBachelorAndMSMajor() {
        let inferred = DeclaredProgramDegreeMetadata.Inference(
            token: "MS",
            fullDegreeType: "Master of Science (MS)",
            degreeLevel: DegreeConfiguration.graduate
        )
        XCTAssertTrue(
            DeclaredProgramDegreeMetadata.shouldUpdateStoredDegreeType(
                current: "Bachelor of Science (BS)",
                inferred: inferred
            )
        )
    }

    func testCombinedTokensReturnNilInference() {
        let inferred = DeclaredProgramDegreeMetadata.infer(fromProgramDisplay: "Accounting BS/MS")
        XCTAssertNil(inferred)
    }

    func testLevelHintFromGraduateCatalogSection() {
        let level = DegreeTypeNormalizer.levelHint(fromCatalogSection: "2024-2025 Graduate Programs Catalog")
        XCTAssertEqual(level, DegreeConfiguration.graduate)
    }

    func testRegistryKnownTokens() {
        XCTAssertTrue(DegreeTokenRegistry.isKnownToken("LLM"))
        XCTAssertTrue(DegreeTokenRegistry.isKnownToken("EDD"))
        XCTAssertFalse(DegreeTokenRegistry.isKnownToken("SCIENCE"))
    }

    func testRequirementsStorageKeyUsesNormalizer() {
        let key = CatalogDegreeTypeFilter.requirementsStorageKey(fromProfileDegreeType: "Master of Science (MS)")
        XCTAssertEqual(key, "MS")
    }
}
