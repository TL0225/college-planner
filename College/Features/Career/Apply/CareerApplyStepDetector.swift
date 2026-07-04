// CareerApplyStepDetector.swift
// Feature: Career / Apply
// Purpose: SPA step state beyond WKNavigationDelegate.didFinish.

import Foundation

struct CareerApplyStepState: Sendable, Equatable {
    var stepId: String
    var platform: JobBoardPlatform
    var frameOrigin: String?
    var mapVersion: String?
}

enum CareerApplyStepDetector {
    static func detectStep(from message: [String: Any], platform: JobBoardPlatform) -> CareerApplyStepState? {
        guard let stepId = message["stepId"] as? String, !stepId.isEmpty else { return nil }
        return CareerApplyStepState(
            stepId: stepId,
            platform: platform,
            frameOrigin: message["frameOrigin"] as? String,
            mapVersion: message["mapVersion"] as? String
        )
    }
}
