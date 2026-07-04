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

    /// Transient network / host blocks that should not fail an entire marathon live suite.
    static func isEnvironmentalLiveCatalogError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .dataNotAllowed:
                return true
            default:
                break
            }
        }
        return isEnvironmentalLiveCatalogMessage(String(describing: error))
    }

    static func isEnvironmentalLiveCatalogMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("nsurlerror domain=-1009")
            || lower.contains("not connected to internet")
            || lower.contains("offline")
            || lower.contains("network connection was lost")
            || lower.contains("nsurlerror domain=-1005")
            || lower.contains("nsurlerror domain=-1001")
            || lower.contains("timed out")
            || lower.contains("connection refused")
            || lower.contains("could not connect to the server")
            || lower.contains("nsurlerror domain=-1004")
            || lower.contains("waf")
            || lower.contains("http 403")
            || lower.contains("http 429")
            || lower.contains("http 503") {
            return true
        }
        return false
    }
}
