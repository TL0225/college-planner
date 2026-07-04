// CareerApplySessionStoreTests.swift
// Feature: Career / Apply Tests

import Foundation
import Testing
@testable import College

@Suite("Career Apply Session Store")
@MainActor
struct CareerApplySessionStoreTests {
    @Test("Open, update, and close session lifecycle")
    func sessionLifecycle() {
        let store = CareerApplySessionStore.shared
        let url = URL(string: "https://boards.greenhouse.io/acme/jobs/1")!
        let session = store.open(
            postingURL: url,
            platform: .greenhouse,
            resumeDocumentID: UUID(),
            resumeFileName: "Resume.pdf",
            companyName: "Acme",
            jobTitle: "Engineer",
            payload: ApplyPayloadFactory.goldenContactPayload()
        )

        #expect(store.session(for: session.id)?.status == .reviewing)

        var updated = session
        updated.status = .filling
        store.update(updated)
        #expect(store.session(for: session.id)?.status == .filling)

        store.close(id: session.id)
        #expect(store.session(for: session.id) == nil)
    }

    @Test("Rebuild payload removes stale temp file when resume is missing")
    func rebuildPayloadCleansStaleTemp() throws {
        let store = CareerApplySessionStore.shared
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-test-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: tempURL)

        var payload = ApplyPayloadFactory.goldenContactPayload()
        payload.documents.resumeFileURL = tempURL

        let session = store.open(
            postingURL: URL(string: "https://boards.greenhouse.io/acme/jobs/1")!,
            platform: .greenhouse,
            resumeDocumentID: payload.documents.resumeDocumentID,
            resumeFileName: payload.documents.resumeFileName,
            companyName: "Acme",
            jobTitle: "Engineer",
            payload: payload
        )

        #expect(throws: CareerApplicationPayloadBuilderError.missingResumeDocument) {
            try store.rebuildPayload(
                for: session.id,
                resumeDocumentID: UUID(),
                collegePersistence: CollegePersistence.shared
            )
        }
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false)

        store.close(id: session.id)
    }

    @Test("Close is idempotent and removes temp resume PDF")
    func closeCleansTempAndIsIdempotent() throws {
        let store = CareerApplySessionStore.shared
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-close-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: tempURL)

        var payload = ApplyPayloadFactory.goldenContactPayload()
        payload.documents.resumeFileURL = tempURL

        let session = store.open(
            postingURL: URL(string: "https://boards.greenhouse.io/acme/jobs/2")!,
            platform: .greenhouse,
            resumeDocumentID: payload.documents.resumeDocumentID,
            resumeFileName: payload.documents.resumeFileName,
            companyName: "Acme",
            jobTitle: "Engineer",
            payload: payload
        )

        store.close(id: session.id)
        store.close(id: session.id)
        #expect(store.session(for: session.id) == nil)
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false)
    }
}
