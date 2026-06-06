import CollegeCalendar
import Foundation

@MainActor
final class CalendarReadPortAdapter: CalendarReadPort {
    static let shared = CalendarReadPortAdapter()

    func eventSnapshots(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) -> [CalendarEventSnapshot] {
        CalendarReadBridge.eventSnapshots(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendarManager: calendarManager
        )
    }

    func eventSnapshotsOffMain(
        rangeStart: Date,
        rangeEnd: Date,
        calendarManager: CalendarIntegrationManager
    ) async -> [CalendarEventSnapshot] {
        await CalendarReadBridge.eventSnapshotsOffMain(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendarManager: calendarManager
        )
    }

    func taskSnapshotsOffMain(rangeStart: Date, rangeEnd: Date) async -> [CalendarTaskSnapshot] {
        await CalendarReadBridge.taskSnapshotsOffMain(rangeStart: rangeStart, rangeEnd: rangeEnd)
    }
}

@MainActor
final class CalendarSearchPortAdapter: CalendarSearchPort {
    static let shared = CalendarSearchPortAdapter()

    func searchOffMain(query: String, limit: Int) async -> [CalendarToolbarSearchMatch] {
        let hits = await CalendarEventSearchBridge.searchOffMain(query: query, semester: nil, limit: limit)
        return hits.map { hit in
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return CalendarToolbarSearchMatch(
                id: hit.id,
                title: hit.title,
                subtitle: df.string(from: hit.startDate)
            )
        }
    }
}

extension CalendarPersistencePortBootstrap {
    @MainActor
    static func wireReadPorts() {
        CalendarReadAccess.reader = CalendarReadPortAdapter.shared
        CalendarReadAccess.search = CalendarSearchPortAdapter.shared
    }
}
