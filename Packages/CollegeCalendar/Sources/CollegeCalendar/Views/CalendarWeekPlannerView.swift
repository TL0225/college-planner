// CalendarWeekPlannerView.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarWeekPlannerView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCalendar

/// Phase 8: week-at-a-glance planner with task time-blocks and deadline markers.
struct CalendarWeekPlannerView: View {
    @Binding var currentDate: Date
    let eventsByDay: [Date: [CalEvent]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week planner")
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
            ForEach(weekDays, id: \.self) { day in
                HStack(alignment: .top, spacing: 8) {
                    Text(day, format: .dateTime.weekday(.abbreviated).day())
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(eventsByDay[day] ?? [], id: \.id) { event in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(event.type == .deadline ? Color.red : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                Text(event.title)
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
    }

    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: currentDate) else { return [] }
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return days
    }
}
