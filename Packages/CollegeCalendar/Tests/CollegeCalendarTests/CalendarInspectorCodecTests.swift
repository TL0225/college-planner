import CollegeCalendar
import Contacts
import XCTest

final class CalendarInspectorCodecTests: XCTestCase {
    func testCalendarEventGuestsCodecRoundTrip() {
        let contact = CNMutableContact()
        contact.givenName = "Ada"
        contact.familyName = "Lovelace"
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ada@example.com" as NSString)]

        let json = CalendarEventGuestsCodec.encode(contacts: [contact])
        XCTAssertNotNil(json)

        let decoded = CalendarEventGuestsCodec.decode(json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "Ada Lovelace")
        XCTAssertEqual(decoded[0].email, "ada@example.com")
    }

    func testCalendarRecurrenceRuleCodecJSONRoundTrip() {
        let payload = """
        {"frequency":"weekly","interval":2,"weekdays":[1,3,5],"endDate":null}
        """
        let settings = CalendarRecurrenceRuleCodec.recurrenceSettings(fromStoredRule: payload)
        XCTAssertEqual(settings.frequency, "weekly")
        XCTAssertEqual(settings.interval, 2)
        XCTAssertEqual(settings.weekdays, [1, 3, 5])

        let google = CalendarRecurrenceRuleCodec.googleRecurrenceArray(from: payload)
        XCTAssertEqual(google?.count, 1)
        XCTAssertTrue(google?.first?.contains("FREQ=WEEKLY") ?? false)
        XCTAssertTrue(google?.first?.contains("INTERVAL=2") ?? false)
        XCTAssertTrue(google?.first?.contains("BYDAY=MO,WE,FR") ?? false)
    }

    func testRecurrenceValidationWeeklyRequiresWeekdays() {
        XCTAssertTrue(CalendarRecurrenceRuleCodec.isSavableRecurrence(frequency: "none", weekdays: []))
        XCTAssertFalse(CalendarRecurrenceRuleCodec.isSavableRecurrence(frequency: "weekly", weekdays: []))
        XCTAssertTrue(CalendarRecurrenceRuleCodec.isSavableRecurrence(frequency: "weekly", weekdays: [2]))
        XCTAssertTrue(CalendarRecurrenceRuleCodec.isSavableRecurrence(frequency: "daily", weekdays: []))
    }

    func testInspectorOnboardingTipTitlesMatchControls() {
        let titles = CalendarInspectorOnboarding.inspectorControlTipTitles()
        XCTAssertEqual(titles.count, 4)
        XCTAssertTrue(titles.contains("Event time and recurrence"))
        XCTAssertTrue(titles.contains("Event location"))
        XCTAssertTrue(titles.contains("Course assignment"))
        XCTAssertTrue(titles.contains("Event details"))
    }

    func testCalendarSyncNotesMetadataParsesCourseUUID() {
        let courseID = UUID()
        let notes = "Office hours\n[course_uuid]=\(courseID.uuidString)"
        XCTAssertEqual(CalendarSyncNotesMetadata.courseUUID(from: notes), courseID)
        XCTAssertNil(CalendarSyncNotesMetadata.courseUUID(from: "No tag here"))
    }

    func testCalendarEventGuestsCodecFlexibleLegacyGooglePayload() {
        let legacy = """
        [{"email":"ada@example.com","displayName":"Ada Lovelace","responseStatus":"accepted"}]
        """
        let decoded = CalendarEventGuestsCodec.decodeFlexible(legacy)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].email, "ada@example.com")
        XCTAssertEqual(decoded[0].responseStatus, "accepted")

        let normalized = CalendarEventGuestsCodec.encode(records: decoded)
        let roundTrip = CalendarEventGuestsCodec.decode(normalized)
        XCTAssertEqual(roundTrip.first?.responseStatus, "accepted")
    }

    func testCalendarCacheKeyPrefersStableEventID() {
        let id = UUID()
        let event = CalendarCalEvent(
            title: "Same Title",
            type: .personal,
            isImportant: false,
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            isAllDay: false,
            calendarEventID: id
        )
        XCTAssertEqual(event.cacheKey, id.uuidString)

        let untitled = CalendarCalEvent(
            title: "Untitled",
            type: .personal,
            isImportant: false,
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            isAllDay: false
        )
        XCTAssertNotEqual(untitled.cacheKey, id.uuidString)
        XCTAssertTrue(untitled.cacheKey.contains("untitled"))
    }

    func testCalendarICalMetadataParsesLocalEventUUID() {
        let eventID = UUID()
        let ical = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:test-uid
        SUMMARY:Hello
        X-COLLEGE-LOCAL-ID:\(eventID.uuidString)
        END:VEVENT
        END:VCALENDAR
        """
        XCTAssertEqual(CalendarICalMetadata.localEventUUID(fromICal: ical), eventID)
    }
}
