// TransferFixtureFactory.swift
// Feature: Transfer / Tests
// Purpose: Seeded equivalencies and mock engines for unit tests and previews.

import Foundation

enum TransferFixtureFactory {
    static func sampleDTO(
        sourceCode: String = "MATH 101",
        targetCode: String = "MATH 1100",
        tier: TransferSourceTier = .official,
        kind: TransferSourceKind = .assist
    ) -> TransferEquivalencyDTO {
        TransferEquivalencyDTO(
            sourceSchoolID: "source-cc",
            sourceSchoolName: "Source CC",
            sourceCourseCode: sourceCode,
            sourceCourseTitle: "College Algebra",
            sourceCredits: 3,
            targetSchoolID: "target-uni",
            targetSchoolName: "Target University",
            targetCourseCode: targetCode,
            targetCourseTitle: "Algebra I",
            targetCredits: 3,
            equivalencyKind: .direct,
            degreeLevel: "undergraduate",
            sourceTier: tier,
            sourceKind: kind,
            externalID: "fixture-\(sourceCode)-\(targetCode)",
            verificationStatus: tier == .official ? .verified : .unverified
        )
    }

    static func corroboratedGroup() -> [TransferEquivalencyDTO] {
        [
            sampleDTO(tier: .community, kind: .githubDataset),
            sampleDTO(tier: .communityVerified, kind: .communityImport),
            sampleDTO(tier: .official, kind: .assist),
        ]
    }

    static func assistAgreementListJSON() -> Data {
        """
        [
          {"key":"fixture-agreement-1","name":"Math","type":"Department"},
          {"key":"fixture-agreement-2","name":"English","type":"Department"}
        ]
        """.data(using: .utf8)!
    }

    static func communityPayloadJSON() -> Data {
        let payload = TransferCommunityPayload(
            version: 1,
            equivalencies: [
                sampleDTO(tier: .community, kind: .githubDataset),
                sampleDTO(sourceCode: "ENG 201", targetCode: "ENGL 2100", tier: .manual, kind: .manualEntry),
            ]
        )
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }
}

struct MockTransferSourceEngine: TransferSourceEngine {
    let sourceKind: TransferSourceKind
    var payload: [TransferEquivalencyDTO]

    init(
        sourceKind: TransferSourceKind = .assist,
        payload: [TransferEquivalencyDTO] = [TransferFixtureFactory.sampleDTO()]
    ) {
        self.sourceKind = sourceKind
        self.payload = payload
    }

    func fetchEquivalencies(
        input: TransferEvaluationInput,
        session: TransferScrapeSession
    ) async throws -> [TransferEquivalencyDTO] {
        payload
    }
}
