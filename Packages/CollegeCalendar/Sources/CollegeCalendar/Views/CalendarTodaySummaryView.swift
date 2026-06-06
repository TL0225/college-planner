// CalendarTodaySummaryView.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTodaySummaryView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Phase 6: compact today summary for sidebar / overview hooks.
struct CalendarTodaySummaryView: View {
    let events: [CalEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
            if events.isEmpty {
                Text("No events").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(4), id: \.id) { event in
                    Text(event.title)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .lineLimit(1)
                }
            }
        }
    }
}
