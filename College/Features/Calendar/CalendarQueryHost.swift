// CalendarQueryHost.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Invalidates calendar caches when local store planner calendar rows change (Phase 7e).
struct CalendarQueryHost: View {
    @Query(sort: [SortDescriptor(\CalendarEvent.startDate, order: .forward)])
    private var calendarEvents: [CalendarEvent]

    @Query(sort: [SortDescriptor(\PlannerTask.dueDate, order: .forward)])
    private var plannerTasks: [PlannerTask]

    let onCalendarRowCountChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                publishChange()
            }
            .onChange(of: calendarEvents.count) { _, _ in publishChange() }
            .onChange(of: plannerTasks.count) { _, _ in publishChange() }
    }

    private func publishChange() {
        onCalendarRowCountChange()
    }
}
