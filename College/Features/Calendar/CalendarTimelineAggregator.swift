// CalendarTimelineAggregator.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTimelineAggregator.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Applies tenant metadata before `CalendarCacheEngine.buildCaches`.
enum CalendarTimelineAggregator {
    static func enrich(
        events: [CalendarEventSnapshot],
        eventsByID: [UUID: CalendarEvent]
    ) -> [CalendarEventSnapshot] {
        events.map { snapshot in
            guard let id = snapshot.calendarEventID,
                  let event = eventsByID[id] else { return snapshot }
            var copy = snapshot
            copy.tenantKind = CalendarTenantKind.resolve(for: event)
            return copy
        }
    }
}
