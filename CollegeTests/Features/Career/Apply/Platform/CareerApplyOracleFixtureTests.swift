// CareerApplyOracleFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply Oracle Fixtures")
@MainActor
struct CareerApplyOracleFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.oracleCases)
    func zeroWritesTierC(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .manualOnly)
        ApplyAccuracyAssert.requireZeroWrites(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
