// CollegeTestRuntime.swift
// Feature: App
// Purpose: App module — CollegeTestRuntime.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Detects when the app process is hosting `xctest` (unit tests run inside `College.app`).
enum CollegeTestRuntime {
    /// True when launched by XCTest (not UI tests unless they also set this env).
    static var isUnitTestProcess: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Opt-in for tests that crawl live university catalogs (very high memory).
    static var runLiveNetworkTests: Bool {
        ProcessInfo.processInfo.environment["COLLEGE_RUN_LIVE_TESTS"] == "1"
    }
}
