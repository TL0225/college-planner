// CareerApplyGreenhouseFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply Greenhouse Fixtures")
@MainActor
struct CareerApplyGreenhouseFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.greenhouseCases)
    func autofillVerifyPass100(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .full)
        ApplyAccuracyAssert.requirePerfectVerifyPass(report)
        ApplyAccuracyAssert.requireNoEEOWrites(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
