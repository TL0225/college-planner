// AcademicCalendarLiveExtractionReportTests.swift
// Feature: Calendar
// Purpose: Live-network extraction report for university academic calendar URLs.

import XCTest
import CollegeCalendar
@testable import College

@MainActor
final class AcademicCalendarLiveExtractionReportTests: XCTestCase {
    private struct SchoolCase: Sendable {
        var name: String
        var url: String
        var timeZoneID: String
        var term: String
        var year: Int
    }

    private let schools: [SchoolCase] = [
        SchoolCase(
            name: "UB Buffalo",
            url: "https://www.buffalo.edu/registrar/calendars/current-academic-calendar.html",
            timeZoneID: "America/New_York",
            term: "Summer",
            year: 2026
        ),
        SchoolCase(
            name: "RIT",
            url: "https://www.rit.edu/calendar",
            timeZoneID: "America/New_York",
            term: "Fall",
            year: 2025
        ),
        SchoolCase(
            name: "DSU",
            url: "https://dsu.edu/academics/academic-calendar.html",
            timeZoneID: "America/Chicago",
            term: "Summer",
            year: 2026
        ),
        SchoolCase(
            name: "NYU",
            url: "https://www.nyu.edu/students/student-information-and-resources/registration-records-and-graduation/academic-calendar.html",
            timeZoneID: "America/New_York",
            term: "Summer",
            year: 2026
        ),
        SchoolCase(
            name: "Stony Brook",
            url: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php",
            timeZoneID: "America/New_York",
            term: "Fall",
            year: 2026
        )
    ]

    private let stonyBrookTermCases: [SchoolCase] = [
        SchoolCase(
            name: "Stony Brook",
            url: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php",
            timeZoneID: "America/New_York",
            term: "Fall",
            year: 2026
        ),
        SchoolCase(
            name: "Stony Brook",
            url: "https://www.stonybrook.edu/commcms/registrar/calendars/academic_calendars.php",
            timeZoneID: "America/New_York",
            term: "Spring",
            year: 2026
        )
    ]

    func testStonyBrookFallAndSpringLiveExtraction() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        var lines: [String] = ["# Stony Brook Fall/Spring Live Extraction Report", ""]

        for school in stonyBrookTermCases {
            do {
                let report = try await extractReportViaScrapeService(for: school)
                lines.append("## \(school.name) — \(school.term) \(school.year)")
                lines.append("- Followed URL: \(report.followedURL)")
                lines.append("- Classification: \(report.classification)")
                lines.append("- Estimated date mentions in fetched content: \(report.estimatedDateMentions)")
                lines.append("- Parsed events (all terms): \(report.allEvents.count)")
                lines.append("- Parsed events (\(school.term) \(school.year)): \(report.scopedEvents.count)")
                lines.append("- Coverage ratio (scoped / date mentions): \(report.coverageLabel)")
                if !report.sampleTitles.isEmpty {
                    lines.append("- Sample events:")
                    for title in report.sampleTitles {
                        lines.append("  - \(title)")
                    }
                }
                if let note = report.note {
                    lines.append("- Note: \(note)")
                }
                XCTAssertTrue(
                    report.scopedEvents.count >= 8,
                    "Expected at least 8 \(school.term) \(school.year) events for Stony Brook, got \(report.scopedEvents.count)"
                )
            } catch {
                lines.append("## \(school.name) — \(school.term) \(school.year)")
                lines.append("- Error: \(error.localizedDescription)")
                XCTFail(error.localizedDescription)
            }
            lines.append("")
        }

        let reportText = lines.joined(separator: "\n")
        print(reportText)
        let attachment = XCTAttachment(string: reportText)
        attachment.name = "stonybrook-fall-spring-live-report.md"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func extractReportViaScrapeService(for school: SchoolCase) async throws -> ExtractionReport {
        let scope = AcademicCalendarImportedScope(term: school.term, year: school.year, level: .all)
        var config = AcademicCalendarConfig(
            schoolID: "stonybrook_\(school.term.lowercased())_\(school.year)",
            name: school.name,
            url: school.url,
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: school.timeZoneID,
            levelScope: .undergrad,
            importedScopes: [scope],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )

        let output = await AcademicCalendarScrapeService.scrape(
            config: &config,
            reason: .manual,
            writeChanges: false
        )
        XCTAssertFalse(output.needsHubPicker, "Hub picker required for \(school.term) \(school.year)")

        let scoped = output.result.parsedEvents
        let followedURL = config.chosenSubCalendarURL ?? school.url
        let fetch = try await AcademicCalendarFetcher.fetch(urlString: followedURL, etag: nil, lastModified: nil)
        let baseURL = URL(string: followedURL) ?? URL(string: school.url)!
        let classification = AcademicCalendarPageClassifier.classify(
            content: fetch.content,
            baseURL: baseURL,
            forcedMode: nil
        )

        let allEvents = scoped
        let sample = scoped.prefix(8).map { event in
            let day = AcademicCalendarIdentityResolver.dayString(event.startDate, timeZoneID: school.timeZoneID)
            return "\(day) · \(event.title)"
        }

        return ExtractionReport(
            classification: String(describing: classification.kind),
            followedURL: followedURL,
            estimatedDateMentions: estimateDateMentions(fetch.content),
            allEvents: allEvents,
            scopedEvents: scoped,
            feedURL: classification.icsFeedURL,
            sampleTitles: Array(sample),
            note: config.lastError,
            error: nil
        )
    }

    func testLiveExtractionReportForAllSchools() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        var lines: [String] = ["# Academic Calendar Live Extraction Report", ""]

        for school in schools {
            do {
                let report = try await extractReport(for: school)
                lines.append("## \(school.name)")
                lines.append("- URL: \(school.url)")
                lines.append("- Classification: \(report.classification)")
                lines.append("- Followed URL: \(report.followedURL)")
                lines.append("- Estimated date mentions in fetched content: \(report.estimatedDateMentions)")
                lines.append("- Parsed events (all terms): \(report.allEvents.count)")
                lines.append(
                    "- Parsed events (\(school.term) \(school.year)): \(report.scopedEvents.count)"
                )
                lines.append("- Coverage ratio (scoped / date mentions): \(report.coverageLabel)")
                if let feed = report.feedURL {
                    lines.append("- Feed URL: \(feed)")
                }
                if !report.sampleTitles.isEmpty {
                    lines.append("- Sample events:")
                    for title in report.sampleTitles {
                        lines.append("  - \(title)")
                    }
                }
                if let note = report.note {
                    lines.append("- Note: \(note)")
                }
                if let error = report.error {
                    lines.append("- Error: \(error)")
                }
            } catch {
                lines.append("## \(school.name)")
                lines.append("- URL: \(school.url)")
                lines.append("- Error: \(error.localizedDescription)")
            }
            lines.append("")
        }

        let reportText = lines.joined(separator: "\n")
        print(reportText)

        let attachment = XCTAttachment(string: reportText)
        attachment.name = "academic-calendar-live-report.md"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Informational only — report is the deliverable for manual review.
        XCTAssertFalse(lines.isEmpty)
    }

    private struct ExtractionReport {
        var classification: String
        var followedURL: String
        var estimatedDateMentions: Int
        var allEvents: [AcademicCalendarParsedEvent]
        var scopedEvents: [AcademicCalendarParsedEvent]
        var feedURL: String?
        var sampleTitles: [String]
        var note: String?
        var error: String?

        var coverageLabel: String {
            guard estimatedDateMentions > 0 else { return "n/a" }
            let ratio = Double(scopedEvents.count) / Double(estimatedDateMentions)
            return String(format: "%.0f%%", min(ratio, 1.0) * 100)
        }
    }

    private func extractReport(for school: SchoolCase) async throws -> ExtractionReport {
        let scope = AcademicCalendarImportedScope(term: school.term, year: school.year, level: .all)
        let config = AcademicCalendarConfig(
            schoolID: school.name.lowercased().replacingOccurrences(of: " ", with: "_"),
            name: school.name,
            url: school.url,
            chosenSubCalendarURL: nil,
            forcedMode: nil,
            timeZoneID: school.timeZoneID,
            levelScope: .all,
            importedScopes: [scope],
            etag: nil,
            lastContentHash: nil,
            lastSuccessfulEventCount: 0,
            lastAttemptedAt: nil,
            lastSuccessfulAt: nil,
            lastError: nil
        )

        var followedURL = school.url
        var fetch = try await AcademicCalendarFetcher.fetch(urlString: school.url, etag: nil, lastModified: nil)
        guard let baseURL = URL(string: school.url) else {
            throw URLError(.badURL)
        }

        var classification = AcademicCalendarPageClassifier.classify(
            content: fetch.content,
            baseURL: baseURL,
            forcedMode: nil
        )
        var note: String?

        if classification.kind == .indexHub {
            let termScope = AcademicCalendarTermScope.Resolved(
                term: school.term,
                year: school.year,
                label: "\(school.term) \(school.year)",
                level: .all
            )
            if AcademicCalendarHubSuggestion.shouldAutoFollow(
                candidates: classification.subCalendars,
                collegeName: school.name,
                degreeLevel: nil,
                termScope: termScope
            ), let autoURL = AcademicCalendarHubSuggestion.bestMatch(
                candidates: classification.subCalendars,
                collegeName: school.name,
                degreeLevel: nil,
                termScope: termScope
            ) {
                followedURL = autoURL
                fetch = try await AcademicCalendarFetcher.fetch(urlString: autoURL, etag: nil, lastModified: nil)
                if let subBase = URL(string: autoURL) {
                    let subClassification = AcademicCalendarPageClassifier.classify(
                        content: fetch.content,
                        baseURL: subBase,
                        forcedMode: nil
                    )
                    classification = subClassification
                    if subClassification.kind == .indexHub,
                       let secondURL = AcademicCalendarHubSuggestion.bestMatch(
                           candidates: subClassification.subCalendars,
                           collegeName: school.name,
                           degreeLevel: nil,
                           termScope: termScope
                       ),
                       secondURL != autoURL {
                        followedURL = secondURL
                        fetch = try await AcademicCalendarFetcher.fetch(urlString: secondURL, etag: nil, lastModified: nil)
                        if let secondBase = URL(string: secondURL) {
                            classification = AcademicCalendarPageClassifier.classify(
                                content: fetch.content,
                                baseURL: secondBase,
                                forcedMode: nil
                            )
                        }
                    }
                }
            } else if !classification.subCalendars.isEmpty {
                note = "Hub auto-select skipped for \(school.term) \(school.year) (\(classification.subCalendars.count) candidates)."
            }
        }

        if classification.kind != .hasICSFeed, followedURL != school.url {
            let termScope = AcademicCalendarTermScope.Resolved(
                term: school.term,
                year: school.year,
                label: "\(school.term) \(school.year)",
                level: .all
            )
            if let calendarURL = deepestCalendarURL(from: classification.subCalendars, termScope: termScope),
               calendarURL != followedURL {
                followedURL = calendarURL
                fetch = try await AcademicCalendarFetcher.fetch(urlString: calendarURL, etag: nil, lastModified: nil)
                if let calendarBase = URL(string: calendarURL) {
                    classification = AcademicCalendarPageClassifier.classify(
                        content: fetch.content,
                        baseURL: calendarBase,
                        forcedMode: nil
                    )
                }
            }
        }

        var allEvents: [AcademicCalendarParsedEvent] = []

        switch classification.kind {
        case .hasICSFeed:
            if let feedURL = classification.icsFeedURL {
                allEvents = try await importFeed(
                    feedURL: feedURL,
                    config: config,
                    subCalendarURL: followedURL
                )
            }
        case .indexHub, .calendar:
            allEvents = AcademicCalendarDeterministicParser.parse(
                content: fetch.content,
                config: config,
                subCalendarURL: followedURL
            )
            if allEvents.isEmpty {
                note = "Deterministic parser found no events; page may need rendered HTML or hub follow-up."
            } else if allEvents.count < max(3, estimateDateMentions(fetch.content) / 3) {
                note = "Partial coverage — some date mentions may be in accordions or JS-only sections."
            }
        }

        let scoped = classification.kind == .hasICSFeed
            ? allEvents.filter { event in
                let year = Calendar.current.component(.year, from: event.startDate)
                return year == school.year
            }
            : AcademicCalendarEventParser.filterByImportedScopes(allEvents, scopes: [scope])
        let sample = scoped.prefix(8).map { event in
            let day = AcademicCalendarIdentityResolver.dayString(event.startDate, timeZoneID: school.timeZoneID)
            return "\(day) · \(event.title)"
        }

        return ExtractionReport(
            classification: String(describing: classification.kind),
            followedURL: followedURL,
            estimatedDateMentions: estimateDateMentions(fetch.content),
            allEvents: allEvents,
            scopedEvents: scoped,
            feedURL: classification.icsFeedURL,
            sampleTitles: Array(sample),
            note: note,
            error: nil
        )
    }

    private func importFeed(
        feedURL: String,
        config: AcademicCalendarConfig,
        subCalendarURL: String?
    ) async throws -> [AcademicCalendarParsedEvent] {
        guard let url = URL(string: feedURL) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let events = try CalendarFeedParser.parse(data: data, urlString: feedURL)
        return AcademicCalendarEventParser.fromICS(events: events, config: config, subCalendarURL: subCalendarURL)
    }

    private func estimateDateMentions(_ content: String) -> Int {
        let pattern = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}(?:,?\s+\d{4})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
    }

    private func deepestCalendarURL(
        from candidates: [AcademicCalendarSubCalendarCandidate],
        termScope: AcademicCalendarTermScope.Resolved
    ) -> String? {
        let scopeTerm = termScope.term.lowercased()
        let calendarLinks = candidates.filter { candidate in
            let haystack = "\(candidate.label) \(candidate.url)".lowercased()
            guard haystack.contains("/calendar") || candidate.label.localizedCaseInsensitiveContains("calendar") else {
                return false
            }
            if haystack.contains("/calendars/index") || haystack.hasSuffix("/calendars/") {
                return false
            }
            if scopeTerm != "summer", haystack.contains("summer") { return false }
            if scopeTerm != "winter", haystack.contains("winter") { return false }
            if haystack.contains("_undergrad-calendar-") || haystack.contains("_graduate-calendar-") {
                return false
            }
            return true
        }
        guard !calendarLinks.isEmpty else { return nil }
        return AcademicCalendarHubSuggestion.bestMatch(
            candidates: calendarLinks,
            collegeName: nil,
            degreeLevel: nil,
            termScope: termScope
        ) ?? calendarLinks.first?.url
    }
}
