// ApplyWKWebViewTestHarness.swift
// Feature: Career / Apply Tests

import Foundation
import WebKit
@testable import College

@MainActor
enum ApplyWKWebViewTestHarness {
    static func run(fixture: ApplyFixtureCase, tier: CareerApplyTier) async throws -> CareerApplyVerificationReport {
        setenv("COLLEGE_APPLY_TEST_STABILIZATION_MS", "50", 1)

        let fileURL = try resolveFixtureURL(fixture)
        let session = CareerApplySession(
            postingURL: fileURL,
            platform: fixture.platform,
            resumeDocumentID: UUID(),
            resumeFileName: "Resume.pdf",
            companyName: "Fixture Co",
            jobTitle: "Engineer",
            payload: ApplyPayloadFactory.goldenContactPayload()
        )
        let coordinator = CareerApplyCoordinator(session: session)
        coordinator.loadApplyURL()

        try await waitUntil(timeoutSeconds: 10) {
            coordinator.pageLoaded && coordinator.bridgeReady
        }
        if coordinator.pageLoaded && !coordinator.bridgeReady {
            try await injectApplyScripts(into: coordinator.view, platform: fixture.platform)
            try await waitUntil(timeoutSeconds: 5) { coordinator.bridgeReady }
        }
        guard coordinator.pageLoaded else { throw ApplyFixtureError.missingFixture(fixture.htmlResource) }
        guard coordinator.bridgeReady else { throw ApplyFixtureError.bridgeTimeout }

        coordinator.runAutofill()

        if tier == .manualOnly {
            try await Task.sleep(nanoseconds: 500_000_000)
            pumpRunLoop(for: 0.5)
            let report = coordinator.verificationReport
            coordinator.tearDown()
            return CareerApplyVerificationReport(
                fields: report.fields,
                writeAttemptCount: report.writeAttemptCount,
                platform: fixture.platform
            )
        }

        let report = try await waitForReport(coordinator: coordinator, timeoutSeconds: 10)
        coordinator.tearDown()
        return report
    }

    private static func resolveFixtureURL(_ fixture: ApplyFixtureCase) throws -> URL {
        do {
            return try TestFixturePaths.applyHTML(named: fixture.htmlResource)
        } catch {
            throw ApplyFixtureError.missingFixture(fixture.htmlResource)
        }
    }

    private static func waitForReport(
        coordinator: CareerApplyCoordinator,
        timeoutSeconds: TimeInterval
    ) async throws -> CareerApplyVerificationReport {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !coordinator.verificationReport.fields.isEmpty {
                return coordinator.verificationReport
            }
            pumpRunLoop(for: 0.05)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ApplyFixtureError.reportTimeout
    }

    private static func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            pumpRunLoop(for: 0.05)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func pumpRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private static func injectApplyScripts(into webView: WKWebView, platform: JobBoardPlatform) async throws {
        let scriptNames = [
            CareerApplyFieldMapLoader.resourceName(for: platform),
            "CareerApplyMapResolver",
            "CareerApplyJSBridge",
            "CareerApplyAuthBridge",
            platformScriptName(for: platform)
        ].compactMap { $0 }

        for name in scriptNames {
            if name.hasSuffix(".v1") {
                guard
                    let url = Bundle.main.url(forResource: name, withExtension: "json"),
                    let data = try? Data(contentsOf: url),
                    let json = String(data: data, encoding: .utf8)
                else { continue }
                try await evalJS(webView, "window.__collegeCareerApplyFieldMap = \(json);")
                continue
            }
            guard
                let url = Bundle.main.url(forResource: name, withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            try await evalJS(webView, source)
            pumpRunLoop(for: 0.05)
        }
    }

    private static func evalJS(_ webView: WKWebView, _ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func platformScriptName(for platform: JobBoardPlatform) -> String? {
        switch platform {
        case .greenhouse: return "CareerApplyGreenhouse"
        case .lever: return "CareerApplyLever"
        case .workday: return "CareerApplyWorkday"
        case .icims: return "CareerApplyICIMS"
        case .oracle: return "CareerApplyOracle"
        case .talemetry: return "CareerApplyTalemetry"
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return nil
        }
    }
}
