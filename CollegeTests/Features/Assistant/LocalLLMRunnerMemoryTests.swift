// LocalLLMRunnerMemoryTests.swift
// Feature: Shared
// Purpose: Shared module — LocalLLMRunnerMemoryTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class LocalLLMRunnerMemoryTests: XCTestCase {
    func testReleaseModelIdempotent() async {
        await LocalLLMRunner.shared.releaseModel()
        let loaded = await LocalLLMRunner.shared.isLoaded
        XCTAssertFalse(loaded)
        await LocalLLMRunner.shared.releaseModel()
    }

    func testPreWarmIsNoOp() async {
        let url = URL(fileURLWithPath: "/tmp/no-model")
        await LocalLLMRunner.shared.preWarm(modelPath: url)
        let loaded = await LocalLLMRunner.shared.isLoaded
        XCTAssertFalse(loaded)
    }
}
