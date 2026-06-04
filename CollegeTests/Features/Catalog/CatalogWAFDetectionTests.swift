// CatalogWAFDetectionTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogWAFDetectionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CatalogWAFDetectionTests: XCTestCase {
    func testDSUStyleAcalogPage_isNotTreatedAsWAF() {
        let snippet = """
        <noscript><p><span class="error">Javascript is currently not supported, or is disabled by this browser. Please enable Javascript for full functionality.</span></p></noscript>
        <link href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.12/css/select2.min.css" rel="stylesheet" />
        <h1 id="acalog-content">Undergraduate Catalog 2025-2026</h1>
        <a href="preview_program.php?catoid=7&poid=123">Computer Science</a>
        """
        XCTAssertFalse(ModernCampusEngine.htmlLooksLikeWAFOrJSChallenge(snippet))
    }

    func testCloudflareChallengeInterstitial_isTreatedAsWAF() {
        let snippet = """
        <html><body>Just a moment...<script>checking your browser</script></body></html>
        """
        XCTAssertTrue(ModernCampusEngine.htmlLooksLikeWAFOrJSChallenge(snippet))
    }

    func testParseProgramHTML_listsBelowAcalogContentHeading() {
        let snippet = """
        <td class="block_n2_and_content">
        <h1 id="acalog-content">Academic Programs</h1>
        <ul>
        <li><a href="preview_program.php?catoid=44&poid=3718">General Studies, A.A.</a></li>
        <li><a href="preview_program.php?catoid=44&poid=3748">Computer Science, B.S.</a></li>
        </ul>
        </td>
        """
        let programs = ModernCampusEngine.invoke_parseProgramHTML_forTests(
            snippet,
            baseURL: "https://catalog.dsu.edu"
        )
        XCTAssertEqual(programs.count, 2)
        XCTAssertTrue(programs.contains(where: { $0.name.contains("Computer Science") }))
    }

    func testParseProgramHTML_assignsDegreeTypeFromSectionAndNameSuffix() {
        let snippet = """
        <td class="block_n2_and_content">
        <h1 id="acalog-content">Academic Programs</h1>
        <p><strong>Bachelor of Science</strong></p>
        <ul><li><a href="preview_program.php?catoid=44&poid=1">Computer Science, B.S.</a></li></ul>
        <p><strong>Bachelor of Business Administration</strong></p>
        <ul><li><a href="preview_program.php?catoid=44&poid=2">Business, B.B.A.</a></li></ul>
        <p><strong>Associate of Arts</strong></p>
        <ul><li><a href="preview_program.php?catoid=44&poid=3">General Studies, A.A.</a></li></ul>
        <p><strong>Certificate</strong></p>
        <ul><li><a href="preview_program.php?catoid=44&poid=4">Cybersecurity Certificate</a></li></ul>
        </td>
        """
        let programs = ModernCampusEngine.invoke_parseProgramHTML_forTests(
            snippet,
            baseURL: "https://catalog.dsu.edu"
        )
        XCTAssertEqual(programs.count, 4)

        let cs = programs.first { $0.name.contains("Computer Science") }
        XCTAssertEqual(cs?.degreeType, "BS")
        XCTAssertEqual(cs?.type, "Major")

        let biz = programs.first { $0.name.contains("Business") }
        XCTAssertEqual(biz?.degreeType, "BBA")

        let gs = programs.first { $0.name.contains("General Studies") }
        XCTAssertEqual(gs?.degreeType, "AA")

        let cert = programs.first { $0.name.contains("Cybersecurity") }
        XCTAssertEqual(cert?.degreeType, "Certificate")
        XCTAssertEqual(cert?.type, "Certificate")
    }

    func testCatalogDegreeTypeFilter_MS_excludesPhDAndMBA() {
        XCTAssertTrue(
            CatalogDegreeTypeFilter.displayName("Computer Science, M.S.", matchesPicker: "MS")
        )
        XCTAssertTrue(
            CatalogDegreeTypeFilter.displayName("Computer Science, M.S.", matchesPicker: "Master of Science (MS)")
        )
        XCTAssertFalse(
            CatalogDegreeTypeFilter.displayName("Computer Science, Ph.D.", matchesPicker: "MS")
        )
        XCTAssertFalse(
            CatalogDegreeTypeFilter.displayName("General Management, M.B.A.", matchesPicker: "MS")
        )
        XCTAssertFalse(
            CatalogDegreeTypeFilter.displayName("Education and Technology, M.S.Ed.", matchesPicker: "MS")
        )
    }

    func testCatalogDegreeTypeFilter_tabLabelUsesFullTitle() {
        XCTAssertEqual(
            CatalogDegreeTypeFilter.tabDisplayLabel(forDegreeType: "MS"),
            "Master of Science"
        )
        XCTAssertEqual(
            CatalogDegreeTypeFilter.tabDisplayLabel(forDegreeType: "Bachelor of Science (BS)"),
            "Bachelor of Science"
        )
    }
}
