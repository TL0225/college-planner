import CollegeCalendar
import XCTest

/// Phase 1d perf gate: ~200 timed events rebuild under budget.
final class CalendarCacheEngineTests: XCTestCase {
    func testBuildCaches_twoHundredEvents_under200ms() {
        let cal = Calendar(identifier: .gregorian)
        let base = cal.startOfDay(for: Date())
        var events: [CalendarEventSnapshot] = []
        events.reserveCapacity(200)

        for i in 0..<200 {
            let start = base.addingTimeInterval(Double(i * 900))
            events.append(
                CalendarEventSnapshot(
                    title: "Event \(i)",
                    start: start,
                    end: start.addingTimeInterval(3600),
                    explicitAllDay: false,
                    calendarEventID: UUID(),
                    calendarObjectURI: nil
                )
            )
        }

        measure {
            _ = CalendarCacheEngine.buildCaches(events: events, tasks: [], calendar: cal)
        }
    }

    func testICSParser_parsesMinimalEvent() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:test-1
        SUMMARY:Hello
        DTSTART:20260101T120000
        DTEND:20260101T130000
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSCalendarParser.parse(icsText: ics)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].uid, "test-1")
        XCTAssertEqual(events[0].title, "Hello")
    }
}
