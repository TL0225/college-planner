// AcademicCalendarSchoolFixtureTests.swift
// Feature: Calendar
// Purpose: Fixture-based tests for university academic calendar pages.

import XCTest
@testable import College

@MainActor
final class AcademicCalendarSchoolFixtureTests: XCTestCase {
    private let summer2026Scope = AcademicCalendarImportedScope(term: "Summer", year: 2026, level: .all)

    func testBuffaloCurrentCalendarParsesSummer2026Events() throws {
        let html = try fixture(named: "buffalo")
        let config = makeConfig(schoolID: "buffalo", timeZoneID: "America/New_York")
        let events = AcademicCalendarDeterministicParser.parse(content: html, config: config, subCalendarURL: nil)
        XCTAssertGreaterThanOrEqual(events.count, 8)

        let summer = AcademicCalendarEventParser.filterByImportedScopes(events, scopes: [summer2026Scope])
        XCTAssertGreaterThanOrEqual(summer.count, 4)
        XCTAssertTrue(summer.contains(where: { $0.title.localizedCaseInsensitiveContains("first day of classes") }))
    }

    func testRITCalendarParsesFallDates() throws {
        let html = try fixture(named: "rit")
        let config = makeConfig(schoolID: "rit", timeZoneID: "America/New_York")
        let baseURL = URL(string: "https://www.rit.edu/calendar")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        XCTAssertEqual(classification.kind, .calendar)

        let events = AcademicCalendarDeterministicParser.parse(content: html, config: config, subCalendarURL: nil)
        XCTAssertGreaterThanOrEqual(events.count, 10)
        XCTAssertTrue(events.contains(where: { $0.title.localizedCaseInsensitiveContains("classes begin") }))
    }

    func testDSUCalendarParsesMultipleTerms() throws {
        let html = try fixture(named: "dsu")
        let config = makeConfig(schoolID: "dsu", timeZoneID: "America/Chicago")
        let events = AcademicCalendarDeterministicParser.parse(content: html, config: config, subCalendarURL: nil)
        XCTAssertGreaterThanOrEqual(events.count, 12)

        let summer = AcademicCalendarEventParser.filterByImportedScopes(events, scopes: [summer2026Scope])
        XCTAssertFalse(summer.isEmpty)
    }

    func testNYUPageDetectsEmbeddedICSFeed() throws {
        let html = try fixture(named: "nyu")
        let baseURL = URL(string: "https://www.nyu.edu/students/student-information-and-resources/registration-records-and-graduation/academic-calendar.html")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        XCTAssertEqual(classification.kind, .hasICSFeed)
        XCTAssertTrue(classification.icsFeedURL?.contains("events.nyu.edu/live/ical") == true)
    }

    func testStonyBrookHubListsTermCalendars() throws {
        let html = try fixture(named: "stonybrook")
        let baseURL = URL(string: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        XCTAssertEqual(classification.kind, .indexHub)
        XCTAssertTrue(classification.subCalendars.contains(where: { $0.label.localizedCaseInsensitiveContains("Summer 2026") }))
    }

    func testStonyBrookHubAutoSelectsFall2026() throws {
        let html = try fixture(named: "stonybrook")
        let baseURL = URL(string: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        let termScope = AcademicCalendarTermScope.Resolved(term: "Fall", year: 2026, label: "Fall 2026", level: .all)

        XCTAssertTrue(
            AcademicCalendarHubSuggestion.shouldAutoFollow(
                candidates: classification.subCalendars,
                collegeName: "Stony Brook University",
                degreeLevel: DegreeConfiguration.undergraduate,
                termScope: termScope
            )
        )

        let selected = AcademicCalendarHubSuggestion.bestMatch(
            candidates: classification.subCalendars,
            collegeName: "Stony Brook University",
            degreeLevel: DegreeConfiguration.undergraduate,
            termScope: termScope
        )
        XCTAssertTrue(selected?.contains("undergrad-calendar-fall-2026") == true)

        let selectedShortName = AcademicCalendarHubSuggestion.bestMatch(
            candidates: classification.subCalendars,
            collegeName: "Stony Brook",
            degreeLevel: DegreeConfiguration.undergraduate,
            termScope: termScope
        )
        XCTAssertTrue(selectedShortName?.contains("undergrad-calendar-fall-2026") == true)
    }

    func testStonyBrookHubAutoSelectsGraduateSpring2026() throws {
        let html = try fixture(named: "stonybrook")
        let baseURL = URL(string: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        let termScope = AcademicCalendarTermScope.Resolved(term: "Spring", year: 2026, label: "Spring 2026", level: .all)

        let selected = AcademicCalendarHubSuggestion.bestMatch(
            candidates: classification.subCalendars,
            collegeName: "Stony Brook University",
            degreeLevel: DegreeConfiguration.graduate,
            termScope: termScope
        )
        XCTAssertTrue(selected?.contains("graduate-calendar-spring-2026") == true)
    }

    func testStonyBrookHubDoesNotAutoFollowWithoutProgramAudience() throws {
        let html = try fixture(named: "stonybrook")
        let baseURL = URL(string: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        let termScope = AcademicCalendarTermScope.Resolved(term: "Fall", year: 2026, label: "Fall 2026", level: .all)

        XCTAssertFalse(
            AcademicCalendarHubSuggestion.shouldAutoFollow(
                candidates: classification.subCalendars,
                collegeName: "Stony Brook University",
                degreeLevel: nil,
                termScope: termScope
            )
        )
        XCTAssertNil(
            AcademicCalendarHubSuggestion.bestMatch(
                candidates: classification.subCalendars,
                collegeName: "Stony Brook University",
                degreeLevel: nil,
                termScope: termScope
            )
        )
    }

    func testStonyBrookFall2026UndergradCalendarParsesEvents() throws {
        let html = try fixture(named: "stonybrook_fall2026")
        let scope = AcademicCalendarImportedScope(term: "Fall", year: 2026, level: .all)
        let config = makeConfig(schoolID: "stonybrook", timeZoneID: "America/New_York")
        let events = AcademicCalendarDeterministicParser.parse(
            content: html,
            config: config,
            subCalendarURL: "https://www.stonybrook.edu/commcms/registrar/calendars/_undergrad-calendar-fall-2026.php"
        )
        XCTAssertGreaterThanOrEqual(events.count, 15)

        let fall = AcademicCalendarEventParser.filterByImportedScopes(events, scopes: [scope])
        XCTAssertGreaterThanOrEqual(fall.count, 10)
        XCTAssertTrue(fall.contains(where: { $0.title.localizedCaseInsensitiveContains("first day of classes") }))
    }

    func testStonyBrookSpring2026UndergradCalendarParsesEvents() throws {
        let html = try fixture(named: "stonybrook_spring2026")
        let scope = AcademicCalendarImportedScope(term: "Spring", year: 2026, level: .all)
        let config = makeConfig(schoolID: "stonybrook", timeZoneID: "America/New_York")
        let events = AcademicCalendarDeterministicParser.parse(
            content: html,
            config: config,
            subCalendarURL: "https://www.stonybrook.edu/commcms/registrar/calendars/_undergrad-calendar-spring-2026.php"
        )
        XCTAssertGreaterThanOrEqual(events.count, 15)

        let spring = AcademicCalendarEventParser.filterByImportedScopes(events, scopes: [scope])
        XCTAssertGreaterThanOrEqual(spring.count, 10)
        XCTAssertFalse(spring.isEmpty)
    }

    func testBuffaloIsDirectCalendarNotHub() throws {
        let html = try fixture(named: "buffalo")
        let baseURL = URL(string: "https://www.buffalo.edu/registrar/calendars/current-academic-calendar.html")!
        let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
        XCTAssertEqual(classification.kind, .calendar)
    }

    func testFixtureExtractionCountsForAllSchools() throws {
        struct Case { var file: String; var name: String; var term: String; var year: Int; var tz: String }
        let cases = [
            Case(file: "buffalo", name: "UB Buffalo", term: "Summer", year: 2026, tz: "America/New_York"),
            Case(file: "rit", name: "RIT", term: "Fall", year: 2025, tz: "America/New_York"),
            Case(file: "dsu", name: "DSU", term: "Summer", year: 2026, tz: "America/Chicago"),
            Case(file: "nyu", name: "NYU", term: "Summer", year: 2026, tz: "America/New_York"),
            Case(file: "stonybrook_fall2026", name: "Stony Brook", term: "Fall", year: 2026, tz: "America/New_York"),
            Case(file: "stonybrook_spring2026", name: "Stony Brook", term: "Spring", year: 2026, tz: "America/New_York"),
        ]

        var lines = ["# Fixture Extraction Counts (College parser)", ""]
        for item in cases {
            let html = try fixture(named: item.file)
            let scope = AcademicCalendarImportedScope(term: item.term, year: item.year, level: .all)
            let config = AcademicCalendarConfig(
                schoolID: item.file,
                name: item.name,
                url: "https://example.edu",
                chosenSubCalendarURL: nil,
                forcedMode: nil,
                timeZoneID: item.tz,
                levelScope: .all,
                importedScopes: [scope],
                etag: nil,
                lastContentHash: nil,
                lastSuccessfulEventCount: 0,
                lastAttemptedAt: nil,
                lastSuccessfulAt: nil,
                lastError: nil
            )
            let baseURL = URL(string: "https://example.edu/\(item.file)")!
            let classification = AcademicCalendarPageClassifier.classify(content: html, baseURL: baseURL, forcedMode: nil)
            let all = AcademicCalendarDeterministicParser.parse(content: html, config: config, subCalendarURL: nil)
            let scoped = AcademicCalendarEventParser.filterByImportedScopes(all, scopes: [scope])
            let dateMentions = estimateDateMentionsInTest(html)
            lines.append("## \(item.name)")
            lines.append("- Classification: \(classification.kind)")
            lines.append("- Date mentions in HTML: \(dateMentions)")
            lines.append("- Parsed events (all terms): \(all.count)")
            lines.append("- Parsed events (\(item.term) \(item.year)): \(scoped.count)")
            if dateMentions > 0 {
                let pct = min(100, Int((Double(scoped.count) / Double(dateMentions)) * 100))
                lines.append("- Scoped coverage vs date mentions: \(pct)%")
            }
            lines.append("")
        }
        let text = lines.joined(separator: "\n")
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "extraction-counts-report.md"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(lines.count > 2)
    }

    private func estimateDateMentionsInTest(_ content: String) -> Int {
        let pattern = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
    }

    private func fixture(named: String) throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AcademicCalendar/\(named).html")
        if FileManager.default.fileExists(atPath: source.path) {
            return try String(contentsOf: source, encoding: .utf8)
        }

        let bundle = Bundle(for: Self.self)
        let candidates = [
            bundle.url(forResource: named, withExtension: "html", subdirectory: "Fixtures/AcademicCalendar"),
            bundle.url(forResource: named, withExtension: "html", subdirectory: "AcademicCalendar")
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(named).html"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeConfig(schoolID: String, timeZoneID: String) -> AcademicCalendarConfig {
        AcademicCalendarConfig(
            schoolID: schoolID,
            name: schoolID.uppercased(),
            url: "https://example.edu",
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: timeZoneID,
            levelScope: .all,
            importedScopes: [summer2026Scope],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )
    }
}
