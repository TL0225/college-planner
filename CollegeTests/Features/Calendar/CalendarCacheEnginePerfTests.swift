// CalendarCacheEnginePerfTests.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarCacheEnginePerfTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Phase 1d perf gate: ~200 timed events rebuild under budget.
final class CalendarCacheEnginePerfTests: XCTestCase {
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
}
