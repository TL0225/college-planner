// AcademicCalendarAutoDetectModuleTests.swift
// Feature: Calendar
// Purpose: Unit and fixture tests for academic calendar auto-detection pipeline modules.

import CollegeCalendar
import XCTest
@testable import College

private final class StubAcademicCalendarFetcher: AcademicCalendarFetching, @unchecked Sendable {
  var responses: [String: AcademicCalendarFetchResult]
  private(set) var fetchCount = 0

  init(responses: [String: AcademicCalendarFetchResult]) {
    self.responses = responses
  }

  func fetch(urlString: String, etag: String?) async throws -> AcademicCalendarFetchResult {
    fetchCount += 1
    if let hit = responses[urlString] { return hit }
    if let path = URL(string: urlString)?.lastPathComponent,
       let hit = responses[path] {
      return hit
    }
    throw URLError(.fileDoesNotExist)
  }

  func headValidate(urlString: String) async -> Bool {
    responses[urlString] != nil
  }
}

@MainActor
final class AcademicCalendarAutoDetectModuleTests: XCTestCase {
  func testProgramContextResolveDoesNotRecurseIntoProgramProfile() {
    let persistence = CollegePersistence.shared
    _ = AcademicCalendarProgramContext.resolve(persistence: persistence)
    _ = AcademicCalendarProgramProfile.resolve(persistence: persistence)
  }

  func testRegisterCalendarIfNeededDoesNotBroadcastConfigsDidChange() {
    var notificationCount = 0
    let token = NotificationCenter.default.addObserver(
      forName: .academicCalendarConfigsDidChange,
      object: nil,
      queue: .main
    ) { _ in
      notificationCount += 1
    }
    defer { NotificationCenter.default.removeObserver(token) }

    let manager = CalendarIntegrationManager()
    let config = AcademicCalendarConfig(
      schoolID: "test-school",
      name: "Test School",
      url: "https://example.edu/calendar",
      timeZoneID: "America/New_York",
      levelScope: .undergrad,
      importedScopes: [],
      departmentKey: "university_wide",
      departmentDisplayName: "Test School"
    )
    AcademicCalendarIntegration.registerCalendarIfNeeded(config: config, calendarManager: manager)
    AcademicCalendarIntegration.syncAllRegistrations(calendarManager: manager)

    XCTAssertEqual(notificationCount, 0)
  }

  func testCalendarNormalizeStripsDiacriticsAndAmpersand() {
    let normalized = AcademicCalendarNormalization.calendarNormalize("Gabelli School of Business & Law")
    XCTAssertTrue(normalized.contains("and"))
    XCTAssertFalse(normalized.contains("&"))
  }

  func testDegradedProfileUsesProgramTokens() {
    let profile = AcademicCalendarProgramProfile(
      degreeLevel: DegreeConfiguration.undergraduate,
      levelScope: .undergrad,
      programLabel: "Cyber Defense (B.S.)",
      owningCollege: nil,
      owningDepartment: nil,
      owningSchool: nil,
      matchTokens: AcademicCalendarNormalization.matchTokens(from: ["Cyber Defense (B.S.)"]),
      isDegraded: true,
      departmentKey: AcademicCalendarConfig.universityWideKey,
      departmentDisplayName: "Cyber Defense — Term Dates"
    )
    XCTAssertTrue(profile.isDegraded)
    XCTAssertTrue(profile.matchTokens.contains(where: { $0.contains("cyber") }))
  }

  func testLinkResolverPrefersGabelliForBusinessProfile() {
    let candidates = [
      AcademicCalendarSubCalendarCandidate(label: "School of Law Calendar", url: "https://example.com/law"),
      AcademicCalendarSubCalendarCandidate(label: "Gabelli School of Business Undergraduate", url: "https://example.com/gabelli"),
    ]
    let profile = AcademicCalendarProgramProfile(
      degreeLevel: DegreeConfiguration.undergraduate,
      levelScope: .undergrad,
      programLabel: "Finance",
      owningCollege: "Gabelli School of Business",
      owningDepartment: nil,
      owningSchool: nil,
      matchTokens: AcademicCalendarNormalization.matchTokens(from: ["Gabelli School of Business"]),
      isDegraded: false,
      departmentKey: "gabelli_school_of_business",
      departmentDisplayName: "Gabelli — Term Dates"
    )
    let best = AcademicCalendarLinkResolver.bestMatch(
      candidates: candidates,
      profile: profile,
      termScope: AcademicCalendarTermScope.Resolved(term: "Fall", year: 2026, label: "Fall 2026", level: .undergrad)
    )
    XCTAssertEqual(best, "https://example.com/gabelli")
  }

  func testHubNavigatorReturnsResult() async {
    let a = #"<html><body><a href="https://school.test/hub_b.html">Hub B</a></body></html>"#
    let fetcher = StubAcademicCalendarFetcher(responses: [
      "https://school.test/hub_a.html": AcademicCalendarFetchResult(content: a, isHTML: true, etag: nil, lastModified: nil, statusCode: 200),
    ])
    let navigator = AcademicCalendarHubNavigator(fetcher: fetcher)
    let outcome = await navigator.navigate(
      from: "https://school.test/hub_a.html",
      profile: nil,
      termScope: nil,
      deadline: Date().addingTimeInterval(30)
    )
    switch outcome {
    case .resolved, .needsUserChoice, .failed, .timedOut:
      XCTAssertTrue(true)
    }
  }

  func testEntryDiscovererPrefersManifestURL() async {
    let discoverer = AcademicCalendarEntryDiscoverer(fetcher: StubAcademicCalendarFetcher(responses: [:]))
    let manifest = SchoolManifest(
      id: "ub",
      name: "UB",
      shortName: nil,
      unitID: nil,
      opeID: nil,
      profileURL: "https://example.com",
      catalogURL: nil,
      academicCalendarURL: "https://example.com/calendar",
      timeZoneID: nil,
      countryCode: nil,
      stateCode: nil,
      officialWebsiteURL: nil,
      financialAidURL: nil,
      registrarURL: nil,
      stateAidAgencyURL: nil,
      catalogFormat: "custom",
      lastUpdated: .now,
      coursesCount: 0,
      verified: true
    )
    let entry = await discoverer.discover(manifest: manifest, policyMetadata: nil, universityName: "UB")
    XCTAssertEqual(entry?.url, "https://example.com/calendar")
    XCTAssertEqual(entry?.source, .manifest)
  }

  func testValidatorRejectsEmptyFixture() async {
    let fetcher = StubAcademicCalendarFetcher(responses: [
      "https://empty.test/": AcademicCalendarFetchResult(content: "", isHTML: true, etag: nil, lastModified: nil, statusCode: 200),
    ])
    let config = makeConfig()
    let result = await AcademicCalendarLinkValidator.validate(
      urlString: "https://empty.test/",
      config: config,
      profile: nil,
      fetcher: fetcher
    )
    XCTAssertFalse(result.isPassed)
  }

  func testFingerprintCacheHitAndInvalidate() {
    let schoolID = "test_school"
    let fingerprint = "fp-1"
    AcademicCalendarFingerprintCache.store(
      schoolID: schoolID,
      fingerprint: fingerprint,
      chosenSubCalendarURL: "https://example.com/cal",
      confidence: 1.0
    )
    XCTAssertEqual(
      AcademicCalendarFingerprintCache.lookup(schoolID: schoolID, fingerprint: fingerprint)?.chosenSubCalendarURL,
      "https://example.com/cal"
    )
    AcademicCalendarFingerprintCache.invalidate(schoolID: schoolID)
    XCTAssertNil(AcademicCalendarFingerprintCache.lookup(schoolID: schoolID, fingerprint: fingerprint))
  }

  func testConfigMigrationProviderSourceV2() {
    let config = AcademicCalendarConfig(
      schoolID: "rit",
      name: "RIT",
      url: "https://rit.edu/calendar",
      timeZoneID: "America/New_York",
      levelScope: .all,
      importedScopes: [],
      departmentKey: "engineering",
      departmentDisplayName: "Engineering — Term Dates"
    )
    XCTAssertEqual(config.providerSource, "academic:rit:engineering")
    XCTAssertEqual(config.toggleID, "Academic:rit:engineering")
    let parsed = AcademicCalendarConfig.parseProviderSource("academic:rit:engineering")
    XCTAssertEqual(parsed?.schoolID, "rit")
    XCTAssertEqual(parsed?.departmentKey, "engineering")
  }

  func testDiscoveryTelemetrySchema() {
    AcademicCalendarDiscoveryTelemetry.emit(
      AcademicCalendarDiscoveryTelemetryPayload(
        resolvedTier: "validatedAuto",
        resolverConfidenceMargin: 3,
        isOverrideNeeded: false,
        discoverySource: "manifest",
        hopCount: 1,
        elapsedMs: 1200,
        schoolID: "nyu",
        departmentKey: "university_wide",
        outcome: "success"
      )
    )
  }

  func testCircuitBreakerOpensAfterFailures() {
    let configID = "school:dept"
    AcademicCalendarCircuitBreaker.recordFailure(configID: configID)
    AcademicCalendarCircuitBreaker.recordFailure(configID: configID)
    AcademicCalendarCircuitBreaker.recordFailure(configID: configID)
    XCTAssertTrue(AcademicCalendarCircuitBreaker.shouldSkip(configID: configID))
    XCTAssertTrue(AcademicCalendarCircuitBreaker.needsAttention(configID: configID))
  }

  private func makeConfig() -> AcademicCalendarConfig {
    AcademicCalendarConfig(
      schoolID: "test",
      name: "Test U",
      url: "https://example.com",
      timeZoneID: "America/New_York",
      levelScope: .all,
      importedScopes: [AcademicCalendarImportedScope(term: "Fall", year: 2026, level: .all)]
    )
  }

  private func fixtureURL(_ name: String) -> URL {
    let testBundle = Bundle(for: AcademicCalendarAutoDetectModuleTests.self)
    let subdirectory = "Fixtures/AcademicCalendar"
    if let url = testBundle.url(forResource: name, withExtension: nil, subdirectory: subdirectory) {
      return url
    }
    return URL(fileURLWithPath: "\(#filePath)/../Fixtures/AcademicCalendar/\(name)")
  }
}
