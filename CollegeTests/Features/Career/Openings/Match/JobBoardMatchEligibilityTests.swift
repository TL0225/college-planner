// JobBoardMatchEligibilityTests.swift
// Feature: Career / Openings / Match

import Foundation
import Testing
@testable import College

@Suite("JobBoardMatchEligibilityTests")
struct JobBoardMatchEligibilityTests {
    @Test("Parsed resume with content is eligible")
    func parsedResumeEligible() {
        var meta = CareerResumeMetadataV1()
        meta.ingestCompletedAt = .now
        meta.structuredSectionsJSON = """
        {"experience":[{"headingLines":["Engineer"],"bullets":["Built APIs"]}],"projects":[],"skills":[],"links":[]}
        """
        let ctx = JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID())
        #expect(ctx != nil)
    }

    @Test("Target role alone is not eligible")
    func targetRoleOnlyNotEligible() {
        var meta = CareerResumeMetadataV1()
        meta.targetRole = "Software Engineer"
        meta.detectedDomainsJSON = "[\"software\"]"
        #expect(JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()) == nil)
    }

    @Test("List display hidden without resume")
    func listHiddenNoResume() {
        let display = JobBoardMatchEligibility.listDisplay(
            hasParsedResume: false,
            hasPendingParse: false,
            hasUsableJD: true,
            cachedOverallScore: 88
        )
        #expect(display == .hidden)
    }

    @Test("List display awaiting description without JD")
    func listAwaitingDescription() {
        let display = JobBoardMatchEligibility.listDisplay(
            hasParsedResume: true,
            hasPendingParse: false,
            hasUsableJD: false,
            cachedOverallScore: nil
        )
        #expect(display == .awaitingDescription)
    }

    @Test("List display shows cached score only when provided")
    func listScored() {
        let display = JobBoardMatchEligibility.listDisplay(
            hasParsedResume: true,
            hasPendingParse: false,
            hasUsableJD: true,
            cachedOverallScore: 72
        )
        #expect(display == .scored(overall: 72))
    }

    @Test("Canonical sidecar without ingest is match-eligible")
    func canonicalFastPathEligible() {
        var meta = CareerResumeMetadataV1()
        meta.canonicalProfileJSON = """
        {"experience":[{"headingLines":["Engineer"],"bullets":["Built APIs"]}],"projects":[],"skills":[],"links":[]}
        """
        meta.parsedTextHash = CareerResumeHashing.hash(normalizedPlainText: meta.canonicalProfileJSON!)
        #expect(JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()) != nil)
        #expect(JobBoardMatchEligibility.hasPendingResumeParse(in: meta) == false)
    }

    @Test("Stale cache rejected when hash mismatches")
    func staleCacheRejected() {
        let match = CareerResumeJobMatch(
            postingCompanySlug: "acme",
            postingExternalPath: "/job/1",
            resumeDocumentID: UUID()
        )
        match.recommendedForPosting = true
        match.overallScore = 90
        match.descriptionHashAtScore = "old-hash"
        #expect(
            JobBoardMatchEligibility.recommendedOverallScoreIfValid(
                match: match,
                postingDescriptionHash: "new-hash",
                resumeParsedTextHash: nil
            ) == nil
        )
    }

    @Test("Requirements-only hash differs from description-only")
    func requirementsHashChange() {
        let descOnly = CareerResumeHashing.hashJobPostingContent(
            descriptionPlain: "Build APIs",
            requirementsPlain: nil
        )
        let withReq = CareerResumeHashing.hashJobPostingContent(
            descriptionPlain: "Build APIs",
            requirementsPlain: "5 years Swift"
        )
        #expect(descOnly != withReq)
    }
}
