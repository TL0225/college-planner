// CareerApplyE2ESmokeTests.swift
// Feature: Career / Apply Tests

import Foundation
import Testing
@testable import College

@Suite("Career Apply E2E Smoke")
@MainActor
struct CareerApplyE2ESmokeTests {
    @Test("Review payload, fill fixture, verify, and complete session")
    func greenhouseOpenFillVerifyConfirm() async throws {
        let store = CareerApplySessionStore.shared
        let fixture = ApplyFixtureCatalog.greenhouseCases[0]
        let fileURL = try TestFixturePaths.applyHTML(named: fixture.htmlResource)
        let resumeID = UUID()

        let session = store.open(
            postingURL: fileURL,
            platform: fixture.platform,
            resumeDocumentID: resumeID,
            resumeFileName: "Resume.pdf",
            companyName: "Fixture Co",
            jobTitle: "Engineer",
            payload: ApplyPayloadFactory.goldenContactPayload()
        )
        #expect(session.status == .reviewing)
        #expect(store.session(for: session.id) != nil)

        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .full)
        ApplyAccuracyAssert.requirePerfectVerifyPass(report)
        #expect(report.wrongValueCount == 0)

        var filled = session
        filled.status = .readyForOnSiteReview
        filled.verificationReport = report
        store.update(filled)
        #expect(store.session(for: session.id)?.status == .readyForOnSiteReview)

        var completed = filled
        completed.status = .completed
        store.update(completed)
        store.close(id: session.id)
        #expect(store.session(for: session.id) == nil)
    }
}
