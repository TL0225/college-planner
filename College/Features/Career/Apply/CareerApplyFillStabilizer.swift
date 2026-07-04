// CareerApplyFillStabilizer.swift
// Feature: Career / Apply
// Purpose: Swift-side orchestration constants for JS fill stabilization protocol.

import Foundation

enum CareerApplyFillStabilizer {
    static var stabilizationMilliseconds: Int {
        if ProcessInfo.processInfo.environment["COLLEGE_APPLY_TEST_STABILIZATION_MS"] != nil,
           let value = Int(ProcessInfo.processInfo.environment["COLLEGE_APPLY_TEST_STABILIZATION_MS"] ?? "") {
            return value
        }
        return 400
    }

    static let maxRetries = 1
    static let bridgePingTimeoutSeconds: TimeInterval = 3
}

enum ApplyTestConfiguration {
    static var stabilizationMs: Int {
        CareerApplyFillStabilizer.stabilizationMilliseconds
    }
}
