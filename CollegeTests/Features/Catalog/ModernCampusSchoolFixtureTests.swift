// ModernCampusSchoolFixtureTests.swift
// Feature: Catalog
// Purpose: Offline per-school ModernCampus fixture coverage for discovery + extraction.

import XCTest
import SwiftSoup
@testable import College

final class ModernCampusSchoolFixtureTests: XCTestCase {
    private let schoolIDs = [
        "dakota_state_university",
        "rutgers_nb",
        "stony_brook",
        "university_at_buffalo",
    ]

    func testCatalogListFixtures_parseAtLeastOneCatalogDescriptor() throws {
        for schoolID in schoolIDs {
            let html = try fixtureString(schoolID: schoolID, fixtureType: .catalogList)
            let doc = try SwiftSoup.parse(html)
            let descriptors = ModernCampusEngine.parseCatalogListPage(doc: doc, host: host(for: schoolID))
            XCTAssertFalse(descriptors.isEmpty, "\(schoolID)")
        }
    }

    func testProgramListingFixtures_analyzeHasProgramAnchors() throws {
        for schoolID in schoolIDs {
            let html = try fixtureString(schoolID: schoolID, fixtureType: .programListing)
            let sourceURL = try XCTUnwrap(URL(string: "https://\(host(for: schoolID))/index.php?catoid=1"))
            let analysis = CatalogModernCampusHTMLAnalyzer.analyze(
                html: html,
                sourceURL: sourceURL,
                schoolID: schoolID,
                catalogVersionID: "\(schoolID)-fixture"
            )
            XCTAssertGreaterThan(analysis.domFeatures.previewProgramLinkCount, 0, "\(schoolID)")
        }
    }

    func testPreviewProgramFixtures_emitHeadingAndIRNodes() throws {
        for schoolID in schoolIDs {
            let html = try fixtureString(schoolID: schoolID, fixtureType: .previewProgram)
            let sourceURL = try XCTUnwrap(URL(string: "https://\(host(for: schoolID))/preview_program.php?catoid=1&poid=1"))
            let analysis = CatalogModernCampusHTMLAnalyzer.analyze(
                html: html,
                sourceURL: sourceURL,
                schoolID: schoolID,
                catalogVersionID: "\(schoolID)-fixture"
            )
            let (profileID, confidence) = ModernCampusLayoutProfileID.classify(
                domFeatures: analysis.domFeatures,
                host: sourceURL.host
            )
            let ir = CatalogModernCampusHTMLAnalyzer.buildIR(
                schoolID: schoolID,
                catalogVersionID: "\(schoolID)-fixture",
                analysis: analysis,
                layoutProfileID: profileID,
                layoutConfidence: CatalogExtractionConfidence(score: confidence, reasons: ["fixture"])
            )
            XCTAssertFalse(ir.nodes.isEmpty, "\(schoolID)")
            XCTAssertTrue(ir.nodes.contains(where: { $0.kind == .heading }), "\(schoolID)")
        }
    }

    private enum FixtureType {
        case catalogList
        case programListing
        case previewProgram
    }

    private func fixtureString(schoolID: String, fixtureType: FixtureType) throws -> String {
        let filename = switch (schoolID, fixtureType) {
        case ("dakota_state_university", .catalogList): "dsu_catalog_list.html"
        case ("dakota_state_university", .programListing): "dsu_program_listing.html"
        case ("dakota_state_university", .previewProgram): "dsu_preview_program.html"
        case ("rutgers_nb", .catalogList): "rutgers_catalog_list.html"
        case ("rutgers_nb", .programListing): "rutgers_program_listing.html"
        case ("rutgers_nb", .previewProgram): "rutgers_preview_program.html"
        case ("stony_brook", .catalogList): "stony_catalog_list.html"
        case ("stony_brook", .programListing): "stony_program_listing.html"
        case ("stony_brook", .previewProgram): "stony_preview_program.html"
        case ("university_at_buffalo", .catalogList): "ub_catalog_list.html"
        case ("university_at_buffalo", .programListing): "ub_program_listing.html"
        case ("university_at_buffalo", .previewProgram): "ub_preview_program.html"
        default: "unknown.html"
        }
        return try String(
            contentsOf: try TestFixturePaths.url("ModernCampus/\(schoolID)/\(filename)"),
            encoding: .utf8
        )
    }

    private func host(for schoolID: String) -> String {
        switch schoolID {
        case "dakota_state_university": return "catalog.dsu.edu"
        case "rutgers_nb": return "catalogs.rutgers.edu"
        case "stony_brook": return "catalog.stonybrook.edu"
        case "university_at_buffalo": return "catalogs.buffalo.edu"
        default: return "catalog.example.edu"
        }
    }
}
