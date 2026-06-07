// CollegeTests+LiveNetwork.swift
// Feature: Shared
// Purpose: Shared module — CollegeTestsSupport.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

enum CollegeTestsSupport {
    static func skipUnlessLiveNetworkTests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try XCTSkipUnless(
            CollegeTestRuntime.runLiveNetworkTests,
            "Live network tests are skipped by default (high memory). Set COLLEGE_RUN_LIVE_TESTS=1 to enable.",
            file: file,
            line: line
        )
    }
}
