// CareerApplyWorkdayFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply Workday Fixtures")
@MainActor
struct CareerApplyWorkdayFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.workdayCases)
    func autofillVerifyPass100(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .partial)
        ApplyAccuracyAssert.requirePerfectVerifyPass(report)
        ApplyAccuracyAssert.requireNoEEOWrites(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
