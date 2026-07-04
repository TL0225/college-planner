// CareerApplySessionStore.swift
// Feature: Career / Apply
// Purpose: Registry of active apply sessions; opens/closes dedicated apply windows.

import Foundation
import Observation

@MainActor
@Observable
final class CareerApplySessionStore {
    static let shared = CareerApplySessionStore()

    private(set) var sessions: [UUID: CareerApplySession] = [:]

    private init() {}

    func session(for id: UUID) -> CareerApplySession? {
        sessions[id]
    }

    @discardableResult
    func open(
        postingURL: URL,
        platform: JobBoardPlatform,
        resumeDocumentID: UUID,
        resumeFileName: String,
        companyName: String,
        jobTitle: String,
        jobApplicationID: UUID? = nil,
        payload: CareerApplicationAutofillPayload? = nil
    ) -> CareerApplySession {
        let session = CareerApplySession(
            jobApplicationID: jobApplicationID,
            postingURL: postingURL,
            platform: platform,
            resumeDocumentID: resumeDocumentID,
            resumeFileName: resumeFileName,
            companyName: companyName,
            jobTitle: jobTitle,
            status: payload == nil ? .preparing : .reviewing,
            payload: payload
        )
        sessions[session.id] = session
        return session
    }

    func update(_ session: CareerApplySession) {
        sessions[session.id] = session
    }

    /// Rebuilds autofill payload (and temp resume file URL) after the user picks a different resume mid-apply.
    @discardableResult
    func rebuildPayload(
        for sessionID: UUID,
        resumeDocumentID: UUID? = nil,
        collegePersistence: CollegePersistence
    ) throws -> CareerApplySession? {
        guard var session = sessions[sessionID] else { return nil }

        let targetResumeID = resumeDocumentID ?? session.resumeDocumentID

        if let oldURL = session.payload?.documents.resumeFileURL {
            try? FileManager.default.removeItem(at: oldURL)
        }

        guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: targetResumeID) else {
            throw CareerApplicationPayloadBuilderError.missingResumeDocument
        }

        let resumeFileName = doc.customDisplayName ?? doc.fileName
        let resumeFileURL = collegePersistence.decryptedTempURLForStoredRelativePath(
            doc.localRelativePath,
            displayFileName: doc.fileName
        )

        var payload = try CareerApplicationPayloadBuilder.build(
            resumeDocumentID: targetResumeID,
            resumeFileURL: resumeFileURL,
            resumeFileName: resumeFileName,
            collegePersistence: collegePersistence
        )
        payload = CareerATSFieldNormalizer.normalizePayload(payload)

        session.resumeDocumentID = targetResumeID
        session.resumeFileName = resumeFileName
        session.payload = payload
        if session.status != .completed {
            session.status = .reviewing
        }
        sessions[sessionID] = session
        return session
    }

    func close(id: UUID) {
        if let session = sessions[id],
           let tempURL = session.payload?.documents.resumeFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        sessions.removeValue(forKey: id)
    }
}
