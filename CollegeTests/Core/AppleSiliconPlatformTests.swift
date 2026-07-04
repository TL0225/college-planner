// AppleSiliconPlatformTests.swift
// Feature: Core
// Purpose: Platform gating for Apple Silicon Macs.

import XCTest
@testable import College

final class AppleSiliconPlatformTests: XCTestCase {
    func testReport_evaluatesOnHost() {
        let report = AppleSiliconPlatform.report
        XCTAssertFalse(report.deviceName.isEmpty)
        #if arch(arm64)
        XCTAssertTrue(report.isSupported)
        #endif
    }

    func testMLXRequiredThreadgroup_matchesKnownMLXLayout() {
        XCTAssertEqual(AppleSiliconPlatform.mlxRequiredThreadsPerThreadgroup, 16 * 64)
    }

    func testEvaluate_withoutMetal_returnsUnsupportedReport() {
        let report = AppleSiliconPlatform.evaluate()
        XCTAssertFalse(report.deviceName.isEmpty)
        #if arch(arm64)
        XCTAssertTrue(report.isSupported)
        XCTAssertNil(report.requirementMessage)
        if let maxThreads = report.maxThreadsPerThreadgroup {
            XCTAssertEqual(report.isMLXCompatible, maxThreads >= AppleSiliconPlatform.mlxRequiredThreadsPerThreadgroup)
        }
        #else
        XCTAssertFalse(report.isSupported)
        XCTAssertNotNil(report.requirementMessage)
        #endif
    }

    func testMLXCompatible_impliesSupportedOnArm64() {
        #if arch(arm64)
        let report = AppleSiliconPlatform.report
        if report.isMLXCompatible {
            XCTAssertTrue(report.isSupported)
        }
        #endif
    }
}
