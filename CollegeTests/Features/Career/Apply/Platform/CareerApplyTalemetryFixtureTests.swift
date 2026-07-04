// CareerApplyTalemetryFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply Talemetry Fixtures")
@MainActor
struct CareerApplyTalemetryFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.talemetryCases)
    func zeroWritesTierC(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .manualOnly)
        ApplyAccuracyAssert.requireZeroWrites(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
