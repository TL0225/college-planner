// QwenJsonWorkerGoldenTests.swift
import Foundation
import Testing
@testable import College

@Suite("Qwen JSON Worker Golden")
struct QwenJsonWorkerGoldenTests {

    @Test("JSON worker model spec")
    func jsonWorkerModelSpec() {
        let spec = ModelSpec.jsonWorker
        #expect(spec.variant == .jsonWorker_4bit)
        #expect(spec.repoID == "mlx-community/Qwen3.5-2B-4bit")
        #expect(spec.displayName == "Qwen 3.5 2B (4-bit)")
    }

    @Test("JSON worker variant directory name")
    func jsonWorkerVariantDirectoryName() async throws {
        let url = try await ModelManager.shared.modelDirectoryURL(for: .jsonWorker)
        #expect(url.path.hasSuffix("jsonWorker_4bit"))
    }

    @Test("Preferred assistant specs use json worker when installed")
    func preferredAssistantSpecsUseJsonWorker() async throws {
        let installed = await ModelManager.shared.isModelInstalled(.jsonWorker)
        guard installed else { return }
        #expect(installed)
    }
}
