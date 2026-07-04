import XCTest
@testable import CollegeCalendar

final class CalendarFeedParserTests: XCTestCase {
    func testDetectsRSSFeed() {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Calendar</title></channel></rss>
        """
        let data = Data(xml.utf8)
        XCTAssertEqual(CalendarFeedParser.detectKind(urlString: "https://example.com/feed.rss", data: data), .rss)
    }

    func testParsesRSSItems() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>University Calendar</title>
            <item>
              <title>Classes Begin</title>
              <pubDate>Mon, 25 Aug 2025 00:00:00 -0400</pubDate>
              <guid>classes-begin</guid>
            </item>
          </channel>
        </rss>
        """
        let events = try CalendarFeedParser.parse(data: Data(xml.utf8), urlString: "https://example.com/feed.rss", kind: .rss)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Classes Begin")
    }

    func testParsesICSFeed() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:test-1
        SUMMARY:Labor Day
        DTSTART:20250901
        DTEND:20250902
        END:VEVENT
        END:VCALENDAR
        """
        let events = try CalendarFeedParser.parse(data: Data(ics.utf8), urlString: "https://example.com/calendar.ics", kind: .ics)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Labor Day")
    }
}
