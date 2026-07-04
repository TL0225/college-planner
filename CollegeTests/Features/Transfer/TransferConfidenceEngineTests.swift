// TransferConfidenceEngineTests.swift
// Feature: Transfer / Tests
// Purpose: Confidence formula unit tests.

import XCTest
@testable import College

final class TransferConfidenceEngineTests: XCTestCase {
    func testOfficialTierScoresHigh() {
        let context = TransferConfidenceContext(
            group: [TransferFixtureFactory.sampleDTO(tier: .official, kind: .assist)],
            hasValidatedProof: false
        )
        let score = TransferConfidenceEngine.score(context)
        XCTAssertGreaterThanOrEqual(score, 70)
    }

    func testCorroborationIncreasesScore() {
        let single = TransferConfidenceContext(group: [TransferFixtureFactory.sampleDTO(tier: .community, kind: .githubDataset)])
        let multi = TransferConfidenceContext(group: [
            TransferFixtureFactory.sampleDTO(tier: .community, kind: .githubDataset),
            TransferFixtureFactory.sampleDTO(tier: .communityVerified, kind: .communityImport),
        ])
        XCTAssertGreaterThan(
            TransferConfidenceEngine.score(multi),
            TransferConfidenceEngine.score(single)
        )
    }

    func testManualOverrideReplacesComputedScore() {
        let context = TransferConfidenceContext(
            group: [TransferFixtureFactory.sampleDTO()],
            manualOverride: 42
        )
        XCTAssertEqual(TransferConfidenceEngine.score(context), 42)
    }

    func testManualOverrideClamped() {
        let high = TransferConfidenceContext(group: [TransferFixtureFactory.sampleDTO()], manualOverride: 150)
        let low = TransferConfidenceContext(group: [TransferFixtureFactory.sampleDTO()], manualOverride: -5)
        XCTAssertEqual(TransferConfidenceEngine.score(high), 100)
        XCTAssertEqual(TransferConfidenceEngine.score(low), 0)
    }

    func testValidatedProofBoostsScore() {
        let without = TransferConfidenceContext(
            group: [TransferFixtureFactory.sampleDTO(tier: .community, kind: .githubDataset)],
            hasValidatedProof: false
        )
        let withProof = TransferConfidenceContext(
            group: [TransferFixtureFactory.sampleDTO(tier: .community, kind: .githubDataset)],
            hasValidatedProof: true,
            proofScore: 0.9
        )
        XCTAssertGreaterThan(
            TransferConfidenceEngine.score(withProof),
            TransferConfidenceEngine.score(without)
        )
    }
}
