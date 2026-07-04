// DiagnosticsPlatformTests.swift
// Feature: CollegeTests
// Purpose: Unified diagnostics platform regression tests.

import XCTest
@testable import College

final class DiagnosticsPlatformTests: XCTestCase {
    func testDiagnosticsArtifactsIncludesCoreSources() {
        let ids = Set(DiagnosticsArtifacts.all.map(\.id))
        XCTAssertTrue(ids.contains("logs"))
        XCTAssertTrue(ids.contains("crashes"))
        XCTAssertTrue(ids.contains("event_store"))
        XCTAssertTrue(ids.contains("metrickit"))
    }

    func testDiagnosticsRegistrySourceIDs() {
        XCTAssertFalse(DiagnosticsRegistry.sources.isEmpty)
        XCTAssertNotNil(DiagnosticsRegistry.source(for: .catalog))
    }

    func testEventStoreInsertQueryAndCorrelation() async throws {
        let store = DiagnosticsEventStore.shared
        await store.openIfNeeded()
        let correlation = DiagnosticsSession.beginCorrelation(prefix: "test")
        await store.enqueue(DiagnosticsEventEmitRequest(
            subsystem: .catalog,
            severity: .info,
            category: nil,
            code: "CATALOG_IMPORT_STARTED",
            message: "Started",
            correlationID: correlation,
            sessionID: DiagnosticsSession.sessionID,
            timestamp: Date()
        ))
        await store.enqueue(DiagnosticsEventEmitRequest(
            subsystem: .catalog,
            severity: .error,
            category: nil,
            code: "CATALOG_IMPORT_FAILED",
            message: "Failed",
            correlationID: correlation,
            sessionID: DiagnosticsSession.sessionID,
            timestamp: Date()
        ))
        await store.flushPending()

        let thread = await store.fetchRecent(limit: 10, correlationID: correlation)
        XCTAssertGreaterThanOrEqual(thread.count, 2)
        XCTAssertEqual(Set(thread.map(\.correlationID)), [correlation])
        DiagnosticsSession.endCorrelation()
    }

    func testPlainLanguageMappings() {
        let record = DiagnosticsEventRecord(
            id: 1,
            timestamp: Date(),
            sessionID: "s",
            correlationID: nil,
            subsystem: .catalog,
            severity: .error,
            category: nil,
            code: "CATALOG_IMPORT_FAILED",
            message: "raw"
        )
        XCTAssertTrue(DiagnosticsPlainLanguage.summary(for: record).contains("catalog"))
    }

    func testHealthReportProducesBand() async {
        let report = await DiagnosticsHealthReportBuilder.generate()
        XCTAssertFalse(report.headline.isEmpty)
        XCTAssertFalse(report.checks.isEmpty)
    }

    func testSupportSnapshotKeys() async throws {
        let snapshot = await SupportSnapshotGenerator.generate()
        XCTAssertFalse(snapshot.health.isEmpty)
        XCTAssertGreaterThanOrEqual(snapshot.crashes30d, 0)
    }

    func testExportPolicyBasicExcludesVectorIndexes() {
        var note: String?
        let urls = DiagnosticsExportPolicy.policy(for: .basic).resolvedURLs(truncationNote: &note)
        XCTAssertFalse(urls.contains { $0.lastPathComponent.contains("vector") })
    }

    func testCrashReportListingSorted() {
        let urls = CrashReportStore.allReportURLs()
        if urls.count >= 2 {
            let d0 = (try? urls[0].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d1 = (try? urls[1].resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            XCTAssertGreaterThanOrEqual(d0, d1)
        }
    }

    func testDiagnosticsEnvironmentManifest() {
        let manifest = DiagnosticsEnvironment.capture()
        XCTAssertFalse(manifest.build.version.isEmpty)
        XCTAssertFalse(manifest.device.macModel.isEmpty)
    }

    func testLaunchHistoryRingBuffer() {
        LaunchHistoryStore.recordLaunch(durationMs: 1200, footprintMB: 512)
        XCTAssertNotNil(LaunchHistoryStore.latest())
    }

    func testExportRedactorStripsHomePathsAndEmails() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sample = "log at \(home)/Library/Logs/foo.log user@example.com"
        let basic = DiagnosticsExportRedactor.redact(sample, level: .basic)
        XCTAssertFalse(basic.contains(home))
        XCTAssertTrue(basic.contains("[REDACTED_PATH]"))
        XCTAssertTrue(basic.contains("[REDACTED_EMAIL]"))
    }
}
