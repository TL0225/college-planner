// EventsWidget.swift
// Feature: Overview
// Purpose: Overview module — EventsWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  EventsWidget.swift
//  College
//
//  Shows the next 3 upcoming calendar events.
//

import SwiftUI

struct EventsWidget: View {
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @AppStorage("calendarHiddenCourseCodes") private var hiddenCourseCodesRaw: String = ""
    var activePage: Binding<AppPage>
    @State private var dataRefreshToken = 0

    private var hiddenCourseCodes: Set<String> {
        Set(hiddenCourseCodesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var upcomingEvents: [OverviewEventSummary] {
        _ = collegePersistence.calendarDidChangeToken
        _ = dataRefreshToken
        let now = Date()
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return [] }
        let hidden = hiddenCourseCodes
        return Array(
            OverviewReadBridge.upcomingEventSummaries(
                days: 8,
                calendarManager: calendarManager,
                collegePersistence: collegePersistence
            )
            .filter { event in
                guard event.startDate >= end else { return false }
                if let code = event.courseCode, !code.isEmpty, hidden.contains(code) { return false }
                return true
            }
            .prefix(3)
        )
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text("Upcoming Events")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                Button(action: { activePage.wrappedValue = .calendar }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12)).foregroundColor(DesignSystem.Colors.textLight)
                }
                .buttonStyle(.plain)
            }

            Color.clear.frame(height: 14)

            if upcomingEvents.isEmpty {
                Label("No upcoming events", systemImage: "calendar.badge.plus")
                    .font(.system(size: 12)).foregroundColor(DesignSystem.Colors.textLight)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                VStack(spacing: 14) {
                    ForEach(upcomingEvents) { event in
                        upcomingEventRow(event)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    // MARK: - Row

    private func upcomingEventRow(_ event: OverviewEventSummary) -> some View {
        let (monthStr, dayStr, color, bg) = eventDateParts(event)
        let daysUntil: Int = {
            let cal = Calendar.current
            return cal.dateComponents([.day],
                from: cal.startOfDay(for: Date()),
                to: cal.startOfDay(for: event.startDate)).day ?? 0
        }()
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(monthStr).font(.system(size: 9, weight: .bold)).foregroundColor(color)
                Text(dayStr).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(color).lineLimit(1)
            }
            .frame(width: 44, height: 44).background(bg).clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .bold)).foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                let detail = [event.location, formatShortTime(event.startDate)]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " • ")
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 10)).foregroundColor(DesignSystem.Colors.textLight).lineLimit(1)
                }
            }
            Spacer()
            if daysUntil >= 0 {
                Text(daysUntil == 0 ? "Today" : daysUntil == 1 ? "Tomorrow" : "in \(daysUntil)d")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(daysUntil == 0 ? Color(hex: "059669") : Color(hex: "6366F1"))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(daysUntil == 0 ? Color(hex: "D1FAE5") : Color(hex: "EEF2FF"))
                    .clipShape(Capsule())
            }
        }
    }

    private func eventDateParts(_ event: OverviewEventSummary) -> (String, String, Color, Color) {
        let d = event.startDate
        let f = DateFormatter()
        f.dateFormat = "MMM"; let month = f.string(from: d).uppercased()
        f.dateFormat = "d";   let day   = f.string(from: d)
        let colors: [(Color, Color)] = [
            (Color(hex: "EC4899"), Color(hex: "FDF2F8")),
            (Color(hex: "06B6D4"), Color(hex: "ECFEFF")),
            (Color(hex: "A855F7"), Color(hex: "FAF5FF")),
            (Color(hex: "F97316"), Color(hex: "FFF7ED")),
        ]
        let hash = abs(event.title.hashValue) % colors.count
        return (month, day, colors[hash].0, colors[hash].1)
    }

    private func formatShortTime(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "events",
            displayName:   "Upcoming Events",
            description:   "The next 3 calendar events with colored date blocks.",
            category:      .academic,
            iconName:      "calendar.badge.clock",
            accentColor:   Color(hex: "A855F7"),
            defaultHeight: 190,
            minHeight:     150,
            makePreview: { EventsWidgetPreview() }
        )
    }
}

// MARK: - Preview

private struct EventsWidgetPreview: View {
    private let events: [(String, String, Color, Color, String)] = [
        ("MAR", "3",  Color(hex: "EC4899"), Color(hex: "FDF2F8"), "Study Group"),
        ("MAR", "7",  Color(hex: "06B6D4"), Color(hex: "ECFEFF"), "Career Fair"),
        ("MAR", "12", Color(hex: "A855F7"), Color(hex: "FAF5FF"), "Hackathon Kick-off"),
    ]
    var body: some View {
        OverviewCard {
            Text("Upcoming Events")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(DesignSystem.Colors.textMain).padding(.bottom, 10)
            VStack(spacing: 10) {
                ForEach(events.indices, id: \.self) { i in
                    let e = events[i]
                    HStack(spacing: 10) {
                        VStack(spacing: 0) {
                            Text(e.0).font(.system(size: 8, weight: .bold)).foregroundColor(e.2)
                            Text(e.1).font(.system(size: 16, weight: .bold)).foregroundColor(e.2)
                        }
                        .frame(width: 36, height: 36).background(e.3).clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(e.4).font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Spacer()
                    }
                }
            }
        }
    }
}
