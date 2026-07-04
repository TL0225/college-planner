// ProductionEvalSamplerTests.swift
#if DEBUG
import Foundation
import Testing
@testable import College

@Suite("Production Eval Sampler")
struct ProductionEvalSamplerTests {

    @Test("Records anonymized sample")
    func recordsSample() {
        defer { ProductionEvalSampler.resetForTesting() }
        ProductionEvalSampler.recordSample(
            prompt: "What classes do I need?",
            intent: "requirement_explanation",
            routePath: "llmPreferred",
            flagged: true
        )
        let candidates = ProductionEvalSampler.promotionCandidates(limit: 5)
        #expect(candidates.count >= 1)
    }
}
#endif
