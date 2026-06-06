import Foundation

@MainActor
public protocol CalendarReadPort: AnyObject {
    func eventSnapshots(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) -> [CalendarEventSnapshot]

    func eventSnapshotsOffMain(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) async -> [CalendarEventSnapshot]

    func taskSnapshotsOffMain(rangeStart: Date, rangeEnd: Date) async -> [CalendarTaskSnapshot]
}

@MainActor
public protocol CalendarSearchPort: AnyObject {
    func searchOffMain(query: String, limit: Int) async -> [CalendarToolbarSearchMatch]
}

@MainActor
public enum CalendarReadAccess {
    public static weak var reader: (any CalendarReadPort)?
    public static weak var search: (any CalendarSearchPort)?
}
