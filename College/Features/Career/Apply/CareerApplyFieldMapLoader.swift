// CareerApplyFieldMapLoader.swift
// Feature: Career / Apply
// Purpose: Load versioned per-platform field map JSON bundled with apply adapters.

import Foundation
import WebKit

struct CareerApplyFieldMapDefinition: Codable, Sendable {
    var version: String
    var step: String?
    var fields: [CareerApplyFieldMapRule]
}

struct CareerApplyFieldMapRule: Codable, Sendable {
    var payloadKey: String
    var label: String?
    var name: String?
    var automationId: String?
}

enum CareerApplyFieldMapLoader {
    static func resourceName(for platform: JobBoardPlatform) -> String {
        switch platform {
        case .greenhouse: return "CareerApplyGreenhouseFieldMap.v1"
        case .lever: return "CareerApplyLeverFieldMap.v1"
        case .workday: return "CareerApplyWorkdayFieldMap.v1"
        case .icims: return "CareerApplyICIMSFieldMap.v1"
        case .oracle: return "CareerApplyOracleFieldMap.v1"
        case .talemetry: return "CareerApplyTalemetryFieldMap.v1"
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return ""
        }
    }

    static func load(platform: JobBoardPlatform) -> CareerApplyFieldMapDefinition? {
        switch platform {
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return nil
        default:
            break
        }
        let name = resourceName(for: platform)
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let map = try? JSONDecoder().decode(CareerApplyFieldMapDefinition.self, from: data)
        else { return nil }
        return map
    }

    @MainActor
    static func userScript(for platform: JobBoardPlatform) -> WKUserScript? {
        guard
            let map = load(platform: platform),
            let data = try? JSONEncoder().encode(map),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        let source = "window.__collegeCareerApplyFieldMap = \(json);"
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}
