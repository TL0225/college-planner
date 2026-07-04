// CareerResumeEligibilityTests.swift
// Feature: Career / Openings / Resume

import Foundation
import Testing
@testable import College

@Suite("CareerResumeEligibilityTests")
struct CareerResumeEligibilityTests {
    @Test("Ingest pending is not eligible")
    func ingestPending() {
        var meta = CareerResumeMetadataV1()
        meta.structuredSectionsJSON = """
        {"experience":[{"headingLines":["Eng"],"bullets":["Code"]}],"projects":[],"skills":[],"links":[]}
        """
        #expect(JobBoardMatchEligibility.hasPendingResumeParse(in: meta))
        #expect(JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()) == nil)
    }

    @Test("Pick primary prefers latest ingestCompletedAt")
    func pickPrimary() {
        let older = UUID()
        let newer = UUID()
        var oldMeta = CareerResumeMetadataV1()
        oldMeta.ingestCompletedAt = Date(timeIntervalSince1970: 100)
        oldMeta.structuredSectionsJSON = """
        {"experience":[{"headingLines":["A"],"bullets":["a"]}],"projects":[],"skills":[],"links":[]}
        """
        var newMeta = CareerResumeMetadataV1()
        newMeta.ingestCompletedAt = Date(timeIntervalSince1970: 200)
        newMeta.structuredSectionsJSON = """
        {"experience":[{"headingLines":["B"],"bullets":["b"]}],"projects":[],"skills":[],"links":[]}
        """
        let picked = JobBoardMatchEligibility.pickPrimaryResume(documents: [
            (documentID: older, metadata: oldMeta),
            (documentID: newer, metadata: newMeta),
        ])
        #expect(picked?.documentID == newer)
    }
}
