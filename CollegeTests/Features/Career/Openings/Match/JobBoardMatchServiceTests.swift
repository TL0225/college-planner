// JobBoardMatchServiceTests.swift
// Feature: Career / Openings / ATS

import Foundation
import Testing
@testable import College

@Suite("CareerATSServiceGateTests")
struct CareerATSServiceGateTests {
    @Test("Empty job description yields empty bundle fields")
    func emptyJD() async {
        let posting = CareerATSPostingSnapshot(
            postingID: UUID(),
            companySlug: "acme",
            externalPath: "/job/1",
            title: "Engineer",
            jobDescriptionText: "",
            requirementsText: nil,
            descriptionHash: nil
        )
        let bundle = await CareerATSService.shared.scoreAllResumes(
            posting: posting,
            platform: .workday,
            priority: .utility
        )
        #expect(bundle.rows.isEmpty)
    }
}

@Suite("CareerResumeRoleFitAnalyzerGateTests")
struct CareerResumeRoleFitAnalyzerGateTests {
    @Test("Quick alignment returns score for title overlap")
    func quickAlignment() {
        let score = CareerResumeRoleFitAnalyzer.quickAlignment(
            jobTitle: "Software Engineer",
            jobDescription: "Swift and APIs",
            profile: nil,
            targetRole: "Software Engineer",
            detectedDomains: ["software"]
        )
        #expect(score >= 0)
        #expect(score <= 100)
    }

    @Test("Title-only job corpus should not be used for list UI")
    func titleOnlyInternalOnly() {
        let score = CareerResumeRoleFitAnalyzer.quickAlignment(
            jobTitle: "Software Engineer",
            jobDescription: nil,
            profile: nil,
            targetRole: "Software Engineer",
            detectedDomains: []
        )
        #expect(score > 0)
        let display = JobBoardMatchEligibility.listDisplay(
            hasParsedResume: false,
            hasPendingParse: false,
            hasUsableJD: false,
            cachedOverallScore: nil
        )
        #expect(display == .hidden)
    }
}

@Suite("CareerATSScoringProfileTests")
struct CareerATSScoringProfileTests {
    @Test(arguments: JobBoardPlatform.allCases)
    func profileLoads(platform: JobBoardPlatform) {
        let profile = CareerATSScoringProfile.profile(for: platform)
        #expect(!profile.name.isEmpty)
        #expect(profile.keywordWeight + profile.semanticWeight > 0)
    }
}
