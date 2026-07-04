// LocalLLMRunnerMemoryTests.swift
import Foundation
import Testing
@testable import College

@Suite("Local LLM Runner Memory")
struct LocalLLMRunnerMemoryTests {

    @Test("Release model idempotent")
    func releaseModelIdempotent() async {
        await LocalLLMRunner.shared.releaseModel()
        let loaded = await LocalLLMRunner.shared.isLoaded
        #expect(!loaded)
        await LocalLLMRunner.shared.releaseModel()
    }

    @Test("Pre-warm is no-op")
    func preWarmIsNoOp() async {
        let url = URL(fileURLWithPath: "/tmp/no-model")
        await LocalLLMRunner.shared.preWarm(modelPath: url)
        let loaded = await LocalLLMRunner.shared.isLoaded
        #expect(!loaded)
    }
}
