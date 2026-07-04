// JobBoardReadUITests.swift
// Feature: Career / Openings / Read UI

import Foundation
import Testing
@testable import College

@Suite("JobBoardReadUITests")
struct JobBoardReadUITests {
    @Test("Posting key is stable")
    func postingKey() {
        let key = JobBoardOpeningsState.postingKey(companySlug: "acme", externalPath: "/job/1")
        #expect(key == "acme|/job/1")
    }

    @Test("Seen and hidden keys are independent")
    func seenHidden() {
        JobBoardOpeningsState.markPostingSeen(companySlug: "acme", externalPath: "/job/1")
        JobBoardOpeningsState.hidePosting(companySlug: "acme", externalPath: "/job/2")
        #expect(JobBoardOpeningsState.isPostingSeen(companySlug: "acme", externalPath: "/job/1"))
        #expect(JobBoardOpeningsState.isPostingHidden(companySlug: "acme", externalPath: "/job/2"))
    }
}

@Suite("JobBoardListMatchBadgeTests")
struct JobBoardListMatchBadgeTests {
    @Test("No scored percent without usable JD")
    func noScoreWithoutJD() {
        let display = JobBoardMatchEligibility.listDisplay(
            hasParsedResume: true,
            hasPendingParse: false,
            hasUsableJD: false,
            cachedOverallScore: 88
        )
        if case .scored = display {
            Issue.record("Must not show cached score without JD")
        }
        #expect(display == .awaitingDescription)
    }

    @Test("Domains-only metadata does not enable parsed resume")
    func domainsOnly() {
        var meta = CareerResumeMetadataV1()
        meta.detectedDomainsJSON = "[\"software\"]"
        #expect(JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()) == nil)
    }
}
