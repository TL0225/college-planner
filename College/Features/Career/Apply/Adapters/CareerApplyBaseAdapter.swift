// CareerApplyBaseAdapter.swift
// Feature: Career / Apply / Adapters
// Purpose: Shared adapter logic for JS injection and message parsing.

import Foundation
import WebKit

class CareerApplyBaseAdapter: CareerApplyPlatformAdapter {
    let platform: JobBoardPlatform
    let tier: CareerApplyTier
    let mapVersion: String
    private let platformScriptName: String

    init(platform: JobBoardPlatform, platformScriptName: String) {
        self.platform = platform
        self.tier = CareerApplyTierRegistry.tier(for: platform)
        self.mapVersion = CareerApplyTierRegistry.mapVersion(for: platform)
        self.platformScriptName = platformScriptName
    }

    @MainActor
    func userScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        if let mapScript = CareerApplyFieldMapLoader.userScript(for: platform) {
            scripts.append(mapScript)
        }
        if let resolver = loadScript(named: "CareerApplyMapResolver") {
            scripts.append(WKUserScript(source: resolver, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let bridge = loadScript(named: "CareerApplyJSBridge") {
            scripts.append(WKUserScript(source: bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if let auth = loadScript(named: "CareerApplyAuthBridge") {
            scripts.append(WKUserScript(source: auth, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if tier.allowsAutofillWrites, let platformJS = loadScript(named: platformScriptName) {
            scripts.append(WKUserScript(source: platformJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        return scripts
    }

    func handleMessage(_ body: [String: Any], session: inout CareerApplySession) -> CareerApplyVerificationReport? {
        guard let type = body["type"] as? String else { return nil }
        switch type {
        case "bridgePing":
            return nil
        case "fillReport", "verificationReport":
            return parseVerificationReport(body, session: &session)
        case "stepChanged":
            if let step = CareerApplyStepDetector.detectStep(from: body, platform: platform) {
                session.mapVersion = step.mapVersion ?? mapVersion
            }
            return nil
        case "manualOnly":
            session.status = .manualOnly
            session.manualOnlyReason = body["reason"] as? String
            return nil
        default:
            return nil
        }
    }

    private func parseVerificationReport(
        _ body: [String: Any],
        session: inout CareerApplySession
    ) -> CareerApplyVerificationReport? {
        guard let fieldsRaw = body["fields"] as? [[String: Any]] else { return nil }
        let fields: [CareerApplyFieldVerification] = fieldsRaw.compactMap { row in
            guard let key = row["payloadKey"] as? String,
                  let intended = row["intended"] as? String else { return nil }
            let statusRaw = row["status"] as? String ?? CareerApplyFieldStatus.filled.rawValue
            let status = CareerApplyFieldStatus(rawValue: statusRaw) ?? .filled
            return CareerApplyFieldVerification(
                payloadKey: key,
                atsLabel: row["atsLabel"] as? String,
                intended: intended,
                filled: row["filled"] as? String,
                verified: row["verified"] as? Bool ?? false,
                status: status,
                stepId: row["stepId"] as? String,
                frameOrigin: row["frameOrigin"] as? String
            )
        }
        let writeCount = body["writeAttemptCount"] as? Int ?? fields.filter { $0.status == .filled }.count
        let report = CareerApplyVerificationReport(
            fields: fields,
            writeAttemptCount: writeCount,
            mapVersion: mapVersion,
            platform: platform,
            completedAt: Date()
        )
        session.verificationReport = report
        session.status = report.wrongValueCount == 0 ? .readyForOnSiteReview : .filling
        return report
    }

    private func loadScript(named: String) -> String? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "js"),
              let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else { return nil }
        return source
    }
}

final class CareerApplyGreenhouseAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyGreenhouseAdapter()
    private init() { super.init(platform: .greenhouse, platformScriptName: "CareerApplyGreenhouse") }
}

final class CareerApplyLeverAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyLeverAdapter()
    private init() { super.init(platform: .lever, platformScriptName: "CareerApplyLever") }
}

final class CareerApplyWorkdayAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyWorkdayAdapter()
    private init() { super.init(platform: .workday, platformScriptName: "CareerApplyWorkday") }
}

final class CareerApplyICIMSAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyICIMSAdapter()
    private init() { super.init(platform: .icims, platformScriptName: "CareerApplyICIMS") }
}

final class CareerApplyOracleAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyOracleAdapter()
    private init() { super.init(platform: .oracle, platformScriptName: "CareerApplyOracle") }
}

final class CareerApplyTalemetryAdapter: CareerApplyBaseAdapter, @unchecked Sendable {
    static let shared = CareerApplyTalemetryAdapter()
    private init() { super.init(platform: .talemetry, platformScriptName: "CareerApplyTalemetry") }
}
