// QwenJsonWorkerGoldenTests.swift
// Feature: Shared
// Purpose: Shared module — QwenJsonWorkerGoldenTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class QwenJsonWorkerGoldenTests: XCTestCase {

    func testJsonWorkerModelSpec() {
        let spec = ModelSpec.jsonWorker
        XCTAssertEqual(spec.variant, .jsonWorker_4bit)
        XCTAssertEqual(spec.repoID, "mlx-community/Qwen3.5-2B-4bit")
        XCTAssertEqual(spec.displayName, "Qwen 3.5 2B (4-bit)")
    }

    func testJsonWorkerVariantDirectoryName() async throws {
        let url = try await ModelManager.shared.modelDirectoryURL(for: .jsonWorker)
        XCTAssertTrue(url.path.hasSuffix("jsonWorker_4bit"))
    }

    func testPreferredAssistantSpecsUseJsonWorker() async throws {
        let installed = await ModelManager.shared.isModelInstalled(.jsonWorker)
        try XCTSkipUnless(installed, "Qwen JSON worker not installed")
        XCTAssertTrue(installed)
    }
}
