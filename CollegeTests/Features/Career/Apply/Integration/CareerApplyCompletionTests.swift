// CareerApplyCompletionTests.swift
// Feature: Career / Apply Tests

import Foundation
import SwiftData
import Testing
import CollegeCareer
@testable import College

@Suite("Career Apply Completion")
@MainActor
struct CareerApplyCompletionTests {
    @Test("recordApplyCompletion moves to Applied and locks submitted resume")
    func recordApplyCompletion() throws {
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        let context = AppDataStore.shared.profileContext

        let resume = VaultDocument(
            fileName: "Resume.pdf",
            localRelativePath: "vault/resume.pdf"
        )
        context.insert(resume)

        let repo = CareerRepository(context: context)
        let application = try repo.addApplication(
            title: "Engineer",
            company: "Fixture Co",
            postingURLString: "https://example.com/jobs/1",
            jobDescriptionText: "Build things",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .interested
        )

        let session = CareerApplySession(
            jobApplicationID: application.id,
            postingURL: URL(string: "https://boards.greenhouse.io/acme/jobs/1")!,
            platform: .greenhouse,
            resumeDocumentID: resume.id,
            resumeFileName: resume.fileName,
            companyName: "Fixture Co",
            jobTitle: "Engineer",
            payload: ApplyPayloadFactory.goldenContactPayload()
        )

        let appliedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let report = CareerApplyVerificationReport(
            fields: [
                CareerApplyFieldVerification(
                    payloadKey: "personal.email",
                    atsLabel: "Email",
                    intended: "timothy@example.edu",
                    filled: "timothy@example.edu",
                    verified: true,
                    status: .filled
                )
            ],
            writeAttemptCount: 1,
            mapVersion: "greenhouse-map@1.0.0",
            platform: .greenhouse
        )

        try repo.recordApplyCompletion(
            applicationID: application.id,
            session: session,
            appliedAt: appliedAt,
            fillReport: report
        )

        let fetched = try repo.fetchApplication(id: application.id)
        #expect(fetched?.statusRaw == CareerApplicationStatus.applied.rawValue)
        #expect(fetched?.submittedResume?.id == resume.id)
        #expect(fetched?.dateApplied == appliedAt)
        #expect(fetched?.provenanceJSON?.contains("applySessionID") == true)
        #expect(fetched?.provenanceJSON?.contains("wrongValueCount") == true)
    }
}
