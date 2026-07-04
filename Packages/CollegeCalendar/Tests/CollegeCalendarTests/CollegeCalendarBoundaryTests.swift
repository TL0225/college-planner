import CollegeCalendar
import XCTest

final class CollegeCalendarBoundaryTests: XCTestCase {
    func testBoundaryMetadata() {
        XCTAssertEqual(CollegeCalendarBoundary.moduleName, "CollegeCalendar")
        XCTAssertEqual(CollegeCalendarBoundary.migrationOrderRank, 1)
        XCTAssertEqual(CollegeCalendarBoundary.changeNotification, Notification.Name.calendarDidChange)
        XCTAssertEqual(
            CollegeCalendarBoundary.changeNotification.rawValue,
            "com.timothy.college.calendarDidChange"
        )
    }
}
