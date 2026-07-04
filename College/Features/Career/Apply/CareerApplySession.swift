// CareerApplySession.swift
// Feature: Career / Apply
// Purpose: Ephemeral apply session state for dedicated apply windows.

import Foundation

struct CareerApplySessionID: Hashable, Codable, Sendable, Identifiable {
    var id: UUID

    init(_ id: UUID = UUID()) {
        self.id = id
    }
}

enum CareerApplySessionStatus: String, Codable, Sendable {
    case preparing
    case reviewing
    case filling
    case readyForOnSiteReview
    case manualOnly
    case completed
    case cancelled
}

struct CareerApplySession: Identifiable, Sendable {
    let id: UUID
    var jobApplicationID: UUID?
    var postingURL: URL
    var platform: JobBoardPlatform
    var resumeDocumentID: UUID
    var resumeFileName: String
    var companyName: String
    var jobTitle: String
    var status: CareerApplySessionStatus
    var payload: CareerApplicationAutofillPayload?
    var verificationReport: CareerApplyVerificationReport?
    var manualOnlyReason: String?
    var createdAt: Date
    var mapVersion: String?

    var sessionID: CareerApplySessionID { CareerApplySessionID(id) }

    init(
        id: UUID = UUID(),
        jobApplicationID: UUID? = nil,
        postingURL: URL,
        platform: JobBoardPlatform,
        resumeDocumentID: UUID,
        resumeFileName: String,
        companyName: String,
        jobTitle: String,
        status: CareerApplySessionStatus = .preparing,
        payload: CareerApplicationAutofillPayload? = nil,
        verificationReport: CareerApplyVerificationReport? = nil,
        manualOnlyReason: String? = nil,
        createdAt: Date = Date(),
        mapVersion: String? = nil
    ) {
        self.id = id
        self.jobApplicationID = jobApplicationID
        self.postingURL = postingURL
        self.platform = platform
        self.resumeDocumentID = resumeDocumentID
        self.resumeFileName = resumeFileName
        self.companyName = companyName
        self.jobTitle = jobTitle
        self.status = status
        self.payload = payload
        self.verificationReport = verificationReport
        self.manualOnlyReason = manualOnlyReason
        self.createdAt = createdAt
        self.mapVersion = mapVersion
    }
}
