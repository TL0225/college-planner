// BackgroundServiceOnDemandTests.swift
// Phase 2: on-demand registry routing and manifest ID validation.

import XCTest
@testable import College

@MainActor
final class BackgroundServiceOnDemandTests: XCTestCase {
    func testRunOnDemandAcceptsKnownManifestID() async {
        await BackgroundServiceOnDemand.run(id: "catalog_background_sync") { }
    }

    func testRunThrowingPropagatesError() async {
        struct SampleError: Error {}
        do {
            _ = try await BackgroundServiceOnDemand.runThrowing(id: "calendar_sync_ingest") {
                throw SampleError()
            }
            XCTFail("Expected error")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
