// CareerApplyTier.swift
// Feature: Career / Apply
// Purpose: V1 autofill scope tiers per platform.

import Foundation

enum CareerApplyTier: Int, Sendable, Comparable {
    case manualOnly = 0
    case partial = 1
    case full = 2

    static func < (lhs: CareerApplyTier, rhs: CareerApplyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func tier(for platform: JobBoardPlatform) -> CareerApplyTier {
        switch platform {
        case .greenhouse, .lever:
            return .full
        case .workday, .icims:
            return .partial
        case .oracle, .talemetry, .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return .manualOnly
        }
    }

    var allowsAutofillWrites: Bool {
        self != .manualOnly
    }

    var displayName: String {
        switch self {
        case .full: return "Full autofill"
        case .partial: return "Contact + screening"
        case .manualOnly: return "Manual only"
        }
    }
}

enum CareerApplyTierRegistry {
    static func tier(for platform: JobBoardPlatform) -> CareerApplyTier {
        CareerApplyTier.tier(for: platform)
    }

    static func mapVersion(for platform: JobBoardPlatform) -> String {
        switch platform {
        case .greenhouse: return "greenhouse-map@1.0.0"
        case .lever: return "lever-map@1.0.0"
        case .workday: return "workday-map@1.0.0"
        case .icims: return "icims-map@1.0.0"
        case .oracle: return "oracle-map@1.0.0"
        case .talemetry: return "talemetry-map@1.0.0"
        case .builtIn: return "builtin-map@1.0.0-manual"
        case .jobicy: return "jobicy-map@1.0.0-manual"
        case .remoteOK: return "remoteok-map@1.0.0-manual"
        case .yCombinator: return "ycombinator-map@1.0.0-manual"
        case .usajobs: return "usajobs-map@1.0.0-manual"
        case .nycCityJobs: return "nyccityjobs-map@1.0.0-manual"
        case .nyStateJobs: return "nystatejobs-map@1.0.0-manual"
        }
    }
}
