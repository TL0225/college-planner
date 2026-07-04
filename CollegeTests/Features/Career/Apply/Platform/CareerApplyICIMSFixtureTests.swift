// CareerApplyICIMSFixtureTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career Apply iCIMS Fixtures")
@MainActor
struct CareerApplyICIMSFixtureTests {
    @Test(arguments: ApplyFixtureCatalog.icimsCases)
    func autofillVerifyPass100(fixture: ApplyFixtureCase) async throws {
        let report = try await ApplyWKWebViewTestHarness.run(fixture: fixture, tier: .partial)
        ApplyAccuracyAssert.requirePerfectVerifyPass(report)
        let expected = try ApplyExpectedReportLoader.load(named: fixture.expectedResource)
        try ApplyExpectedReportLoader.assertMatchesExpected(report, expected: expected)
    }
}
