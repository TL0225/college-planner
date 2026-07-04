// CatalogPlatformProbeTests.swift
// Feature: Catalog
// Purpose: Regression fixtures for catalog platform detection doctrine.

import XCTest
@testable import College

final class CatalogPlatformProbeTests: XCTestCase {
    func testDetectInHTML_rutgersCoursedog() {
        let html = """
        <html><body><div id="app">coursedog coursedog coursedog</div><a href="/programs">Programs</a></body></html>
        """
        let platform = CatalogPlatformProbe.detectInHTML(html, baseURL: URL(string: "https://catalogs.rutgers.edu"))
        XCTAssertEqual(platform, .coursedog)
    }

    func testDetectInHTML_ufCourseLeaf() {
        let html = """
        <html><head><link rel="stylesheet" href="/courseleaf.css"></head><body><div class="sc_courselist">...</div></body></html>
        """
        let platform = CatalogPlatformProbe.detectInHTML(html, baseURL: URL(string: "https://catalog.ufl.edu/UGRD/"))
        XCTAssertEqual(platform, .courseleaf)
    }

    func testDetectInHTML_georgetownCustomWordpress() {
        let html = """
        <html><body><script src="/wp-json/wp/v2"></script><div class="wp-content">Bulletin</div></body></html>
        """
        let platform = CatalogPlatformProbe.detectInHTML(html, baseURL: URL(string: "https://bulletin.georgetown.edu"))
        XCTAssertEqual(platform, .custom)
    }

    func testDetectInHTML_purdueModernCampus() {
        let html = """
        <html><body><a href="/misc/catalog_list.php">Catalog list</a><a href="content.php?catoid=1&navoid=2">Programs</a><h1 id="acalog-content">Catalog</h1></body></html>
        """
        let platform = CatalogPlatformProbe.detectInHTML(html, baseURL: URL(string: "https://catalog.purdue.edu"))
        XCTAssertEqual(platform, .moderncampus)
    }

    func testSniffURL_pdf() {
        let outcome = CatalogPlatformFingerprintStore.sniffURL("https://www.brooklyn.edu/file.pdf")
        XCTAssertEqual(outcome, .pdf)
    }

    func testAutoOverrideThreshold_requiresConfidenceAndMargin() {
        XCTAssertTrue(
            CatalogPlatformFingerprintStore.shouldAutoOverride(
                declared: .moderncampus,
                detected: .coursedog,
                confidence: 2.0,
                margin: 1.0
            )
        )
        XCTAssertFalse(
            CatalogPlatformFingerprintStore.shouldAutoOverride(
                declared: .moderncampus,
                detected: .coursedog,
                confidence: 1.8,
                margin: 1.0
            )
        )
        XCTAssertFalse(
            CatalogPlatformFingerprintStore.shouldAutoOverride(
                declared: .moderncampus,
                detected: .coursedog,
                confidence: 2.2,
                margin: 0.5
            )
        )
    }
}
