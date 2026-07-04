// CareerApplyPlatformAdapter.swift
// Feature: Career / Apply
// Purpose: Platform-specific apply autofill adapter protocol.

import Foundation
import WebKit

protocol CareerApplyPlatformAdapter: AnyObject {
    var platform: JobBoardPlatform { get }
    var tier: CareerApplyTier { get }
    var mapVersion: String { get }

    @MainActor func userScripts() -> [WKUserScript]
    func handleMessage(_ body: [String: Any], session: inout CareerApplySession) -> CareerApplyVerificationReport?
}

@MainActor
enum CareerApplyAdapterRegistry {
    static func adapter(for platform: JobBoardPlatform) -> any CareerApplyPlatformAdapter {
        switch platform {
        case .greenhouse:
            return CareerApplyGreenhouseAdapter.shared
        case .lever:
            return CareerApplyLeverAdapter.shared
        case .workday:
            return CareerApplyWorkdayAdapter.shared
        case .icims:
            return CareerApplyICIMSAdapter.shared
        case .oracle:
            return CareerApplyOracleAdapter.shared
        case .talemetry:
            return CareerApplyTalemetryAdapter.shared
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return CareerApplyOracleAdapter.shared
        }
    }
}
