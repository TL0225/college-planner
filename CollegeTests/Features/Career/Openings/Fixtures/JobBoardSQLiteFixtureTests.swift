// JobBoardSQLiteFixtureTests.swift
// Feature: Career / Openings / Fixtures

import Foundation
import Testing
@testable import College

private struct JobBoardStoreSnapshot: Decodable {
    struct PostingRow: Decodable {
        let companySlug: String
        let externalPath: String
        let hasJobDescription: Bool
        let detailScrapedAt: String?
        let descriptionHash: String?
        let cachedMatchScore: Int?
        let cachedMatchHash: String?
        let expectedListDisplay: String
    }

    struct ResumeRow: Decodable {
        let ingestCompletedAt: String?
        let hasStructuredContent: Bool
        let targetRole: String?
        let expectedEligible: Bool
    }

    let postings: [PostingRow]
    let resumes: [ResumeRow]
}

@Suite("JobBoardSQLiteFixtureTests")
struct JobBoardSQLiteFixtureTests {
    private static let embeddedFixture = """
    {
      "postings": [
        {
          "companySlug": "nvidia",
          "externalPath": "/job/US-CA/SWE-JR001",
          "hasJobDescription": false,
          "detailScrapedAt": null,
          "expectedListDisplay": "awaitingDescription"
        },
        {
          "companySlug": "nvidia",
          "externalPath": "/job/US-CA/SWE-JR002",
          "hasJobDescription": true,
          "detailScrapedAt": "2026-06-01T12:00:00Z",
          "descriptionHash": "abc123",
          "cachedMatchScore": 78,
          "cachedMatchHash": "abc123",
          "expectedListDisplay": "scored"
        }
      ],
      "resumes": [
        {
          "ingestCompletedAt": null,
          "hasStructuredContent": false,
          "targetRole": "Engineer",
          "expectedEligible": false
        },
        {
          "ingestCompletedAt": "2026-06-01T10:00:00Z",
          "hasStructuredContent": true,
          "expectedEligible": true
        }
      ]
    }
    """

    private func loadSnapshot() throws -> JobBoardStoreSnapshot {
        let data = try #require(Self.embeddedFixture.data(using: .utf8))
        return try JSONDecoder().decode(JobBoardStoreSnapshot.self, from: data)
    }

    @Test("Bulk import without JD stays awaiting description")
    func bulkAwaitingDescription() throws {
        let snapshot = try loadSnapshot()
        for row in snapshot.postings where row.expectedListDisplay == "awaitingDescription" {
            let hasJD = row.hasJobDescription && row.detailScrapedAt != nil
            let display = JobBoardMatchEligibility.listDisplay(
                hasParsedResume: true,
                hasPendingParse: false,
                hasUsableJD: hasJD,
                cachedOverallScore: nil
            )
            #expect(display == .awaitingDescription)
        }
    }

    @Test("Resume fixture eligibility matches golden expectations")
    func resumeEligibility() throws {
        let snapshot = try loadSnapshot()
        for row in snapshot.resumes {
            var meta = CareerResumeMetadataV1()
            if row.ingestCompletedAt != nil { meta.ingestCompletedAt = .now }
            if row.hasStructuredContent {
                meta.structuredSectionsJSON = """
                {"experience":[{"headingLines":["Eng"],"bullets":["Code"]}],"projects":[],"skills":[],"links":[]}
                """
            }
            meta.targetRole = row.targetRole
            let eligible = JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()) != nil
            #expect(eligible == row.expectedEligible)
        }
    }

    @Test("Cached score only when hash matches")
    func cachedScoreGolden() throws {
        let snapshot = try loadSnapshot()
        guard let row = snapshot.postings.first(where: { $0.expectedListDisplay == "scored" }) else {
            Issue.record("Missing scored fixture row")
            return
        }
        let match = CareerResumeJobMatch(
            postingCompanySlug: row.companySlug,
            postingExternalPath: row.externalPath,
            resumeDocumentID: UUID()
        )
        match.recommendedForPosting = true
        match.overallScore = row.cachedMatchScore ?? 0
        match.descriptionHashAtScore = row.cachedMatchHash
        match.resumeHashAtScore = "resume-hash"
        let score = JobBoardMatchEligibility.recommendedOverallScoreIfValid(
            match: match,
            postingDescriptionHash: row.descriptionHash,
            resumeParsedTextHash: "resume-hash"
        )
        #expect(score == row.cachedMatchScore)
    }
}
