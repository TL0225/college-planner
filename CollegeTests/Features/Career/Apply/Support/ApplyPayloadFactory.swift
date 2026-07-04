// ApplyPayloadFactory.swift
// Feature: Career / Apply Tests

import Foundation
@testable import College

enum ApplyPayloadFactory {
    static func goldenContactPayload() -> CareerApplicationAutofillPayload {
        CareerApplicationAutofillPayload(
            personal: ApplyPersonalInfo(
                firstName: "Timothy",
                lastName: "Leung",
                fullName: "Timothy Leung",
                email: "timothy@example.edu",
                phone: "5551234567",
                address: "New York, NY",
                linkedInURL: "https://linkedin.com/in/timothy",
                githubURL: "https://github.com/timothy",
                portfolioURL: nil,
                pronouns: nil
            ),
            education: [],
            experienceBlocks: [],
            projects: [],
            skills: ["Swift"],
            summary: nil,
            documents: ApplyDocuments(
                resumeDocumentID: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
                resumeFileName: "Resume.pdf",
                resumeFileURL: nil,
                coverLetterDocumentID: nil
            ),
            applicationProfile: ApplyApplicationProfile(
                workAuthorization: ApplyWorkAuthorization(
                    usCitizen: false,
                    usAuthorized: true,
                    requiresSponsorshipNow: false,
                    requiresSponsorshipFuture: true
                ),
                preferences: ApplyApplicationDefaults(),
                screeningAnswerCache: [:],
                allowEEOAutofill: false
            ),
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRevisionToken: "test-revision"
        )
    }
}
