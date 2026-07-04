// AcademicCalendarExtractorTests.swift
// Feature: Calendar
// Purpose: Deterministic tests for academic calendar parsing and identity.

import XCTest
@testable import College

@MainActor
final class AcademicCalendarExtractorTests: XCTestCase {
    func testOneLineTitleCollapsesWhitespace() {
        let title = AcademicCalendarTitleNormalizer.oneLineTitle("Last day to\n withdraw ")
        XCTAssertEqual(title, "Last day to withdraw")
    }

    func testNearDuplicateTitles() {
        XCTAssertTrue(
            AcademicCalendarTitleNormalizer.areNearDuplicates(
                "Last Day to Withdraw",
                "Last day to withdraw from a course"
            )
        )
    }

    func testIdentitySignatureStable() {
        let sig1 = AcademicCalendarTitleNormalizer.identitySignature(title: "Classes Begin", startDay: "2025-08-25")
        let sig2 = AcademicCalendarTitleNormalizer.identitySignature(title: "classes begin", startDay: "2025-08-25")
        XCTAssertEqual(sig1, sig2)
    }

    func testParseJSONArray() {
        let config = AcademicCalendarConfig(
            schoolID: "test",
            name: "Test U",
            url: "https://example.com",
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: "America/New_York",
            levelScope: .all,
            importedScopes: [],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )
        let json = """
        [{"title":"Classes Begin","startDate":"2025-08-25","endDate":"2025-08-25","allDay":true,"status":"confirmed","term":"Fall","year":2025,"level":"all","confidence":0.9}]
        """
        let events = AcademicCalendarEventParser.parseJSONArray(json, config: config, subCalendarURL: nil)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Classes Begin")
    }

    func testScrapedIdentityKeyCarriesAcrossRewording() {
        let config = AcademicCalendarConfig(
            schoolID: "ub",
            name: "UB",
            url: "https://example.com",
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: "America/New_York",
            levelScope: .all,
            importedScopes: [],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )
        let scope = AcademicCalendarIdentityResolver.makeScopeKey(term: "Fall", year: 2025, level: .all, subCalendarURL: nil)
        let day = "2025-08-25"
        let key1 = AcademicCalendarIdentityResolver.scrapedIdentityKey(schoolID: "ub", scopeKey: scope, title: "Last Day to Withdraw", startDay: day)
        let key2 = AcademicCalendarIdentityResolver.scrapedIdentityKey(schoolID: "ub", scopeKey: scope, title: "Last day to withdraw from a course", startDay: day)
        XCTAssertNotEqual(key1, key2)

        let ledgerEntry = AcademicCalendarLedgerEntry(
            localID: UUID(),
            identityKey: key1,
            identitySignature: AcademicCalendarTitleNormalizer.identitySignature(title: "Last Day to Withdraw", startDay: day),
            scopeKey: scope,
            importedSnapshot: AcademicCalendarImportedSnapshot(
                title: "Last Day to Withdraw",
                startDate: AcademicCalendarTimezone.allDayStart(of: Date(), timeZoneID: config.timeZoneID),
                endDate: AcademicCalendarTimezone.allDayStart(of: Date(), timeZoneID: config.timeZoneID),
                allDay: true,
                notes: nil,
                status: .confirmed
            ),
            status: .confirmed,
            confidence: 0.9,
            promptVersion: AcademicCalendarPrompt.version,
            userModified: false,
            lastSeenScrapeID: nil
        )

        let incoming = AcademicCalendarParsedEvent(
            id: key2,
            title: "Last day to withdraw from a course",
            startDate: ledgerEntry.importedSnapshot.startDate,
            endDate: ledgerEntry.importedSnapshot.endDate,
            allDay: true,
            status: .confirmed,
            term: "Fall",
            year: 2025,
            level: .all,
            confidence: 0.9,
            scopeKey: scope,
            identityKey: key2,
            identitySignature: AcademicCalendarTitleNormalizer.identitySignature(title: "Last day to withdraw from a course", startDay: day),
            providerEventId: nil,
            notes: nil,
            isLowConfidence: false
        )

        let match = AcademicCalendarIdentityResolver.matchIncoming(event: incoming, ledger: [ledgerEntry], schoolID: "ub")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.entry.localID, ledgerEntry.localID)
    }

    func testICSIdentityFallbackSignature() {
        let uidKey = AcademicCalendarIdentityResolver.icsIdentityKey(uid: "abc")
        let signature = AcademicCalendarTitleNormalizer.identitySignature(title: "Labor Day", startDay: "2025-09-01")
        XCTAssertTrue(uidKey.hasPrefix("ics:"))
        XCTAssertTrue(signature.contains("labor"))
    }

    func testParseDayRangeProducesSpanningAllDayBoundaries() throws {
        let config = makeTestConfig()
        let json = """
        [{"title":"Thanksgiving Break","startDate":"2025-11-26","endDate":"2025-11-28","allDay":true,"status":"confirmed","term":"Fall","year":2025,"level":"all","confidence":0.9}]
        """
        let events = AcademicCalendarEventParser.parseJSONArray(json, config: config, subCalendarURL: nil)
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        let tz = config.timeZoneID
        XCTAssertEqual(
            AcademicCalendarIdentityResolver.dayString(event.startDate, timeZoneID: tz),
            "2025-11-26"
        )
        XCTAssertEqual(
            AcademicCalendarIdentityResolver.dayString(
                event.endDate.addingTimeInterval(-86_400),
                timeZoneID: tz
            ),
            "2025-11-28"
        )
    }

    func testCrossScopeMoveDetection() {
        let scopeFall = AcademicCalendarIdentityResolver.makeScopeKey(term: "Fall", year: 2025, level: .all, subCalendarURL: nil)
        let scopeWinter = AcademicCalendarIdentityResolver.makeScopeKey(term: "Winter", year: 2025, level: .all, subCalendarURL: nil)
        let signature = AcademicCalendarTitleNormalizer.identitySignature(title: "Reading Day", startDay: "2025-12-12")
        let removed = AcademicCalendarLedgerEntry(
            localID: UUID(),
            identityKey: "scraped:old",
            identitySignature: signature,
            scopeKey: scopeFall,
            importedSnapshot: AcademicCalendarImportedSnapshot(
                title: "Reading Day",
                startDate: Date(),
                endDate: Date(),
                allDay: true,
                notes: nil,
                status: .confirmed
            ),
            status: .confirmed,
            confidence: 0.9,
            promptVersion: 1,
            userModified: false,
            lastSeenScrapeID: nil
        )
        let added = AcademicCalendarParsedEvent(
            id: "scraped:new",
            title: "Reading Day",
            startDate: Date(),
            endDate: Date(),
            allDay: true,
            status: .confirmed,
            term: "Winter",
            year: 2025,
            level: .all,
            confidence: 0.9,
            scopeKey: scopeWinter,
            identityKey: "scraped:new",
            identitySignature: signature,
            providerEventId: nil,
            notes: nil,
            isLowConfidence: false
        )
        let pairs = AcademicCalendarIdentityResolver.detectCrossScopeMoves(removed: [removed], added: [added])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.removed.scopeKey, scopeFall)
        XCTAssertEqual(pairs.first?.added.scopeKey, scopeWinter)
    }

    func testStateTimezoneFallback() {
        let manifest = SchoolManifest(
            id: "dakota_state_university",
            name: "DSU",
            shortName: "DSU",
            unitID: nil,
            opeID: nil,
            profileURL: "https://example.edu/profile.json",
            catalogURL: "https://catalog.dsu.edu/",
            academicCalendarURL: nil,
            timeZoneID: nil,
            countryCode: "US",
            stateCode: "SD",
            officialWebsiteURL: nil,
            financialAidURL: nil,
            registrarURL: nil,
            stateAidAgencyURL: nil,
            catalogFormat: "acalog",
            lastUpdated: Date(),
            coursesCount: 0,
            verified: false
        )
        XCTAssertEqual(AcademicCalendarTimezone.resolve(manifest: manifest), "America/Chicago")
    }

    func testFilterByImportedScopes() {
        let config = makeTestConfig()
        let json = """
        [
          {"title":"Fall Start","startDate":"2025-08-25","endDate":"2025-08-25","allDay":true,"status":"confirmed","term":"Fall","year":2025,"level":"all","confidence":0.9},
          {"title":"Spring Start","startDate":"2026-01-12","endDate":"2026-01-12","allDay":true,"status":"confirmed","term":"Spring","year":2026,"level":"all","confidence":0.9}
        ]
        """
        let events = AcademicCalendarEventParser.parseJSONArray(json, config: config, subCalendarURL: nil)
        let filtered = AcademicCalendarEventParser.filterByImportedScopes(
            events,
            scopes: [AcademicCalendarImportedScope(term: "Fall", year: 2025, level: .all)]
        )
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.term, "Fall")
    }

    func testFullSnapshotGuardBlocksMassDrop() {
        XCTAssertFalse(AcademicCalendarUpsertService.shouldAllowRemovals(priorCount: 100, incomingCount: 0))
        XCTAssertFalse(AcademicCalendarUpsertService.shouldAllowRemovals(priorCount: 100, incomingCount: 40))
        XCTAssertTrue(AcademicCalendarUpsertService.shouldAllowRemovals(priorCount: 100, incomingCount: 60))
        XCTAssertTrue(AcademicCalendarUpsertService.shouldAllowRemovals(priorCount: 0, incomingCount: 12))
    }

    func testJSONSanitizerWrappedPayload() {
        let config = makeTestConfig()
        let json = """
        ```json
        {"events":[{"title":"Labor Day","startDate":"2025-09-01","endDate":"2025-09-01","allDay":true,"status":"confirmed","term":"Fall","year":2025,"level":"all","confidence":0.9}]}
        ```
        """
        let events = AcademicCalendarEventParser.parseJSONArray(json, config: config, subCalendarURL: nil)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Labor Day")
    }

    func testDeterministicTableParser() {
        let config = makeTestConfig()
        let html = """
        <table>
          <tr><th colspan="2">Fall 2025</th></tr>
          <tr><td>August 25, 2025</td><td>Classes Begin</td></tr>
          <tr><td>November 26, 2025</td><td>Thanksgiving Break Begins</td></tr>
        </table>
        """
        let events = AcademicCalendarDeterministicParser.parse(content: html, config: config, subCalendarURL: nil)
        XCTAssertGreaterThanOrEqual(events.count, 2)
        XCTAssertTrue(events.contains(where: { $0.title == "Classes Begin" }))
    }

    func testDeterministicTextLineParser() {
        let config = makeTestConfig()
        let text = """
        Fall 2025
        August 25, 2025 - Classes Begin
        September 1, 2025 - Labor Day
        """
        let events = AcademicCalendarDeterministicParser.parse(content: text, config: config, subCalendarURL: nil)
        XCTAssertGreaterThanOrEqual(events.count, 2)
        XCTAssertTrue(events.contains(where: { $0.title == "Classes Begin" }))
    }

    private func makeTestConfig() -> AcademicCalendarConfig {
        AcademicCalendarConfig(
            schoolID: "test",
            name: "Test U",
            url: "https://example.com",
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: "America/New_York",
            levelScope: .all,
            importedScopes: [],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )
    }
}
