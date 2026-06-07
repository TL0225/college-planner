// CatalogExternalReferenceBuilderTests.swift
// Feature: Shared
// Purpose: ExternalReference population from engine-native course IDs.

import XCTest
@testable import College

final class CatalogExternalReferenceBuilderTests: XCTestCase {
    func testReferences_moderncampusCoid() {
        let course = CatalogCourse(
            courseCode: "CSE 115",
            title: "Intro",
            credits: 3,
            catalogCoid: "12345",
            previewDetailURL: "https://catalog.example.edu/preview_course_nopop.php?coid=12345"
        )
        let refs = CatalogExternalReferenceBuilder.references(for: course, engine: "moderncampus")
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs.first?.system, "moderncampus")
        XCTAssertEqual(refs.first?.externalID, "12345")
    }

    func testEnriching_addsReferences() {
        let course = CatalogCourse(
            courseCode: "CSE 115",
            title: "Intro",
            credits: 3,
            catalogCoid: "99",
            previewDetailURL: "https://example.edu/course"
        )
        let enriched = CatalogExternalReferenceBuilder.enriching(course, engine: "moderncampus")
        XCTAssertFalse(enriched.externalReferences.isEmpty)
    }

    func testArticulationRows_mergeWhenCapabilityEnabled() {
        let schoolID = "articulation_fixture_\(UUID().uuidString)"
        CatalogManifestCapabilityStore.save(
            CatalogManifestCapabilities(
                supportsTransferEquivalencies: true,
                supportsArticulationIngest: true
            ),
            schoolID: schoolID
        )
        CatalogArticulationReferenceStore.save(
            [
                CatalogArticulationRow(
                    courseCode: "CSE 115",
                    system: "transferology",
                    externalID: "tl-115",
                    url: "https://transferology.com/course/tl-115"
                ),
            ],
            schoolID: schoolID
        )
        let course = CatalogCourse(courseCode: "CSE 115", title: "Intro", credits: 3)
        let refs = CatalogExternalReferenceBuilder.references(
            for: course,
            engine: "courseleaf",
            schoolID: schoolID
        )
        XCTAssertTrue(refs.contains(where: { $0.system == "transferology" && $0.externalID == "tl-115" }))
    }
}
