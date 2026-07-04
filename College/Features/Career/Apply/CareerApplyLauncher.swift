// CareerApplyLauncher.swift
// Feature: Career / Apply
// Purpose: Open apply session + dedicated window from job detail or tracker.

import SwiftUI

@MainActor
enum CareerApplyLauncher {
    @discardableResult
    static func openApplyInCollege(
        postingURL: URL,
        platform: JobBoardPlatform,
        resumeDocumentID: UUID,
        resumeFileName: String,
        companyName: String,
        jobTitle: String,
        jobApplicationID: UUID?,
        openWindow: OpenWindowAction,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter? = nil
    ) -> Bool {
        let parserHealth = resumeParserHealth(
            resumeDocumentID: resumeDocumentID,
            collegePersistence: collegePersistence
        )

        let gate = CareerApplyAccuracyGate.evaluate(
            applyURL: postingURL,
            resumeDocumentID: resumeDocumentID,
            parserHealthPercent: parserHealth,
            collegePersistence: collegePersistence
        )
        guard gate.allowed else {
            notifications?.post(
                kind: .warning,
                title: "Can't open Apply in College",
                message: gate.userFacingBlockMessage
            )
            return false
        }

        let resumeFileURL = decryptedResumeTempURL(
            resumeDocumentID: resumeDocumentID,
            collegePersistence: collegePersistence
        )

        guard var payload = try? CareerApplicationPayloadBuilder.build(
            resumeDocumentID: resumeDocumentID,
            resumeFileURL: resumeFileURL,
            resumeFileName: resumeFileName,
            collegePersistence: collegePersistence
        ) else {
            notifications?.post(
                kind: .warning,
                title: "Can't open Apply in College",
                message: "Could not build autofill data from your resume."
            )
            return false
        }

        payload = CareerATSFieldNormalizer.normalizePayload(payload)

        let session = CareerApplySessionStore.shared.open(
            postingURL: postingURL,
            platform: platform,
            resumeDocumentID: resumeDocumentID,
            resumeFileName: resumeFileName,
            companyName: companyName,
            jobTitle: jobTitle,
            jobApplicationID: jobApplicationID,
            payload: payload
        )
        openWindow(id: "career-apply", value: session.sessionID)
        ProductAnalytics.track(.resumeApplyLaunched, properties: ["platform": platform.rawValue])

        if !gate.warnings.isEmpty {
            notifications?.post(
                kind: .info,
                title: "Apply in College",
                message: gate.warnings.joined(separator: " ")
            )
        }
        return true
    }

    private static func resumeParserHealth(
        resumeDocumentID: UUID,
        collegePersistence: CollegePersistence
    ) -> Int? {
        guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: resumeDocumentID) else {
            return nil
        }
        return collegePersistence.careerResumeMetadata(for: doc).parserHealthPercent
    }

    private static func decryptedResumeTempURL(
        resumeDocumentID: UUID,
        collegePersistence: CollegePersistence
    ) -> URL? {
        guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: resumeDocumentID) else {
            return nil
        }
        return collegePersistence.decryptedTempURLForStoredRelativePath(
            doc.localRelativePath,
            displayFileName: doc.fileName
        )
    }
}

private extension CareerApplyAccuracyGateResult {
    var userFacingBlockMessage: String {
        reasons.map { reason in
            switch reason {
            case .missingEmail:
                return "Add your university email in Profile before applying."
            case .missingProfile:
                return "Complete your profile before applying."
            case .missingApplyURL:
                return "This posting does not have a valid apply URL."
            case .criticalParserHealth:
                return "Resume parser health is too low — re-analyze your resume first."
            case .missingWorkAuthorization:
                return "Set work authorization in Apply Profile."
            case .payloadBuildFailed:
                return "Could not build autofill data from your resume."
            }
        }.joined(separator: " ")
    }
}
