// CareerApplyLeverFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply Lever Fixtures")
@MainActor
struct CareerApplyLeverFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.leverCases)
    func autofillVerifyPass100(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .full)
        ApplyAccuracyAssert.requirePerfectVerifyPass(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
