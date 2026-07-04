// JobBoardPipelineE2ETests.swift
// Feature: Career / Openings / Integration

import Foundation
import SwiftData
import Testing
@testable import College

@Suite("JobBoardPipelineE2ETests")
@MainActor
struct JobBoardPipelineE2ETests {
    @Test("Import detail score promote chain")
    func pipelineChain() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let context = AppDataStore.shared.profileContext
        let repo = CareerRepository(context: context)
        let company = JobBoardCompany(slug: "acme", displayName: "Acme", careersURL: "https://acme.example/jobs")
        let resumeID = UUID()
        let resume = VaultDocument(
            id: resumeID,
            fileName: "Resume.pdf",
            localRelativePath: "vault/resume.pdf"
        )
        context.insert(resume)

        _ = try repo.applyJobBoardListings(company: company, listings: [
            ScrapedJobListing(
                externalId: "JR-1",
                externalPath: "/job/1",
                title: "Software Engineer",
                locationText: "Remote",
                postedOn: nil,
                applyURLString: "https://acme.example/apply",
                jobTypeText: nil,
                timeType: nil,
                listingHash: "hash-1"
            ),
        ])

        let bridgeResults = JobBoardReadBridge.companyPostings(companySlug: "acme")
        #expect(bridgeResults.count == 1)

        let posting = try #require(try repo.fetchPosting(companySlug: "acme", externalPath: "/job/1"))
        #expect(JobBoardMatchEligibility.hasUsableJobDescription(posting) == false)

        try repo.applyJobBoardDetail(
            posting: posting,
            detail: ScrapedJobDetail(
                title: "Software Engineer",
                descriptionPlain: "Build APIs with Swift and distributed systems.",
                requirementsPlain: "3+ years experience",
                locationDisplay: "Remote",
                filterLocations: [],
                postedAt: nil,
                postedOnDisplay: nil,
                workModel: nil,
                jobTypeText: nil,
                timeType: nil,
                salaryText: nil
            )
        )
        #expect(JobBoardMatchEligibility.hasUsableJobDescription(posting))

        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: resumeID,
            overallScore: 76,
            keywordScore: 70,
            semanticScore: 72,
            experienceScore: 65,
            missingKeywords: ["kubernetes"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: posting.descriptionHash,
            resumeHash: "resume-hash"
        )

        let match = try repo.recommendedMatchIfValid(
            companySlug: "acme",
            externalPath: "/job/1",
            postingDescriptionHash: posting.descriptionHash,
            resumeParsedTextHash: "resume-hash"
        )
        #expect(match?.overallScore == 76)

        let app = try repo.promoteJobBoardPostingToTracker(posting, recommendedResumeID: resumeID)
        #expect(app.workdaySourcePosting?.externalPath == "/job/1")
        #expect(app.submittedResume?.id == resumeID)
        #expect(app.resumeDisplayName == "Resume.pdf")
        #expect(app.matchScoreAtSubmission == 76)
        #expect(app.submittedResumeContentHash == "resume-hash")

        let session = CareerApplySessionStore.shared.open(
            postingURL: URL(string: "https://acme.example/apply")!,
            platform: .greenhouse,
            resumeDocumentID: resumeID,
            resumeFileName: "Resume.pdf",
            companyName: "Acme",
            jobTitle: "Software Engineer",
            jobApplicationID: app.id,
            payload: nil
        )
        #expect(session.jobApplicationID == app.id)
        #expect(session.resumeDocumentID == resumeID)
        #expect(CareerApplySessionStore.shared.session(for: session.id)?.jobApplicationID == app.id)
    }
}
