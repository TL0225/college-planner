// CareerApplyVerificationReport.swift
// Feature: Career / Apply
// Purpose: Intended / Filled / Verified model for zero-wrong-fill contract.

import Foundation

enum CareerApplyFieldStatus: String, Codable, Sendable {
    case filled
    case skipped
    case ambiguous
    case skippedShadowDOM = "skipped_shadow_dom"
    case unstableField = "unstable_field"
    case wrongValue = "wrong_value"
    case manualOnly = "manual_only"
}

struct CareerApplyFieldVerification: Codable, Sendable, Equatable, Identifiable {
    var id: String { payloadKey }
    var payloadKey: String
    var atsLabel: String?
    var intended: String
    var filled: String?
    var verified: Bool
    var status: CareerApplyFieldStatus
    var stepId: String?
    var frameOrigin: String?
}

struct CareerApplyVerificationReport: Codable, Sendable, Equatable {
    var fields: [CareerApplyFieldVerification]
    var writeAttemptCount: Int
    var mapVersion: String?
    var platform: JobBoardPlatform?
    var completedAt: Date?

    var wrongValueCount: Int {
        fields.filter { $0.status == .wrongValue || (!$0.verified && $0.status == .filled) }.count
    }

    static var empty: CareerApplyVerificationReport {
        CareerApplyVerificationReport(fields: [], writeAttemptCount: 0)
    }
}
