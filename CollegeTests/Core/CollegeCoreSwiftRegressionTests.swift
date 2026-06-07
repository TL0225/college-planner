// CollegeCoreSwiftRegressionTests.swift
// Feature: Shared
// Purpose: Shared module — CollegeCoreSwiftRegressionTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Swift-fallback coverage for `CollegeCore` (runs without `COLLEGE_CORE_RUST_LINKED`).
final class CollegeCoreSwiftRegressionTests: XCTestCase {
    func testNormalizeCourseCodeFallback() {
        XCTAssertEqual(CollegeCore.normalizeCourseCode("cse\u{00A0}116"), "CSE 116")
        XCTAssertEqual(CollegeCore.normalizeCourseCode("  mth   142 "), "MTH 142")
    }

    func testExtractCourseCodesFallback() {
        let codes = CollegeCore.extractCourseCodes(from: "Need CSE 116 or MTH 142 before CSE 220.")
        XCTAssertEqual(Set(codes), Set(["CSE 116", "MTH 142", "CSE 220"]))
    }

    func testParsePrereqWithoutRustReturnsNil() {
        XCTAssertNil(CollegeCore.parsePrereq("CSE 116 and MTH 142"))
    }
}
