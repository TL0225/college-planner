// CalendarPersistenceBridges.swift
// Feature: Calendar
// Purpose: App-target adapters between SwiftData models and CollegeCalendar package types.

import CollegeCalendar
import Foundation

extension CalendarTenantKind {
    static func resolve(for event: CalendarEvent) -> CalendarTenantKind {
        let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolve(
            courseCode: code.isEmpty ? nil : code,
            providerSource: event.providerSource,
            hasCourse: event.course != nil
        )
    }
}

extension CalendarVisibilityFilter {
    func shouldDisplay(_ event: CalendarEvent) -> Bool {
        let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return shouldDisplay(
            CalendarVisibilityEventInput(
                localID: event.id.uuidString,
                providerSource: event.providerSource,
                courseCode: code.isEmpty ? nil : code
            )
        )
    }
}

extension CalendarTimelineAggregator {
    static func enrich(
        events: [CalendarEventSnapshot],
        eventsByID: [UUID: CalendarEvent]
    ) -> [CalendarEventSnapshot] {
        let tenantKindByEventID = eventsByID.mapValues { CalendarTenantKind.resolve(for: $0) }
        return enrich(events: events, tenantKindByEventID: tenantKindByEventID)
    }
}
