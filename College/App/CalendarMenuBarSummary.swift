// CalendarMenuBarSummary.swift
// Feature: App
// Purpose: App module — CalendarMenuBarSummary.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Phase 9: menu bar today summary (local store-first reads).
struct CalendarMenuBarSummary: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var todayEvents: [OverviewEventSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
            if todayEvents.isEmpty {
                Text("No upcoming events").foregroundStyle(.secondary)
            } else {
                ForEach(todayEvents.prefix(5)) { event in
                    HStack {
                        Text(event.title)
                        Spacer()
                        Text(event.startDate, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    .font(DesignSystem.Fonts.main(size: 12))
                }
            }
            Divider()
            Button("Open College") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { refreshTodayEvents() }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in refreshTodayEvents() }
    }

    private func refreshTodayEvents() {
        todayEvents = OverviewReadBridge.todayEventSummaries(collegePersistence: collegePersistence)
    }
}
