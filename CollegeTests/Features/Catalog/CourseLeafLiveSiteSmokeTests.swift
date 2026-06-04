// CourseLeafLiveSiteSmokeTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafLiveSiteSmokeTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafLiveSiteSmokeTests: XCTestCase {
    func testFordhamCourseLeafLiveCrawl() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let output = try await CourseLeafEngine.crawlCatalog(
            baseURL: "https://bulletin.fordham.edu/",
            schoolID: "fordham_university"
        )
        XCTAssertFalse(output.sourceSignature.isEmpty)
        XCTAssertGreaterThan(output.courses.count, 0, "Expected at least one course from Fordham")
        XCTAssertGreaterThan(output.programs.count, 0, "Expected at least one program from Fordham")
    }

    func testCMUCourseLeafLiveCrawl() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let output = try await CourseLeafEngine.crawlCatalog(
            baseURL: "http://coursecatalog.web.cmu.edu/",
            schoolID: "carnegie_mellon_university"
        )
        XCTAssertFalse(output.sourceSignature.isEmpty)
        XCTAssertGreaterThan(output.courses.count, 0, "Expected at least one course from CMU")
        XCTAssertGreaterThan(output.programs.count, 0, "Expected at least one program from CMU")
    }

    func testNYUCourseLeafLiveCrawl() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        let output = try await CourseLeafEngine.crawlCatalog(
            baseURL: "https://bulletins.nyu.edu/",
            schoolID: "new_york_university"
        )
        XCTAssertFalse(output.sourceSignature.isEmpty)
        XCTAssertGreaterThan(output.courses.count, 0, "Expected at least one course from NYU")
        XCTAssertGreaterThan(output.programs.count, 0, "Expected at least one program from NYU")
    }
}
