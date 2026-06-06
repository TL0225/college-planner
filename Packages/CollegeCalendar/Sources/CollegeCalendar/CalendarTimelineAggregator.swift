import Foundation

/// Applies tenant metadata before `CalendarCacheEngine.buildCaches`.
public enum CalendarTimelineAggregator {
    public static func enrich(
        events: [CalendarEventSnapshot],
        tenantKindByEventID: [UUID: CalendarTenantKind]
    ) -> [CalendarEventSnapshot] {
        events.map { snapshot in
            guard let id = snapshot.calendarEventID,
                  let kind = tenantKindByEventID[id] else { return snapshot }
            var copy = snapshot
            copy.tenantKind = kind
            return copy
        }
    }
}
