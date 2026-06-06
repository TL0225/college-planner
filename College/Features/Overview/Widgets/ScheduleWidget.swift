// ScheduleWidget.swift
import CollegeCalendar
// Feature: Overview
// Purpose: Overview module — ScheduleWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  ScheduleWidget.swift
//  College
//
//  Today's classes and events with live countdown badges.
//

import SwiftUI

struct ScheduleWidget: View {
    @Environment(AppContainer.self) private var container
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    private var persistence: CollegePersistence { container.persistence }
        private var collegePersistence: CollegePersistence { container.persistence }
    @AppStorage("calendarHiddenCourseCodes") private var hiddenCourseCodesRaw: String = ""
    @State private var dataRefreshToken = 0

    private var hiddenCourseCodes: Set<String> {
        Set(hiddenCourseCodesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var todaysEvents: [OverviewEventSummary] {
        _ = collegePersistence.calendarDidChangeToken
        _ = dataRefreshToken
        let hidden = hiddenCourseCodes
        return OverviewReadBridge.todayEventSummaries(
            calendarManager: calendarManager,
            collegePersistence: collegePersistence
        )
        .filter { event in
            if let code = event.courseCode, !code.isEmpty, hidden.contains(code) { return false }
            return true
        }
        .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text("Today's Schedule")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                Text(dayOfWeekLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "F3F4F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Color.clear.frame(height: 14)

            if todaysEvents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20)).foregroundColor(DesignSystem.Colors.textLight)
                    Text("No classes or events scheduled for today")
                        .font(.system(size: 12)).foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(todaysEvents.prefix(4))) { event in
                        scheduleEventRow(event)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    // MARK: - Row

    private struct TimeBadge { let text: String; let textColor: Color; let bgColor: Color }

    private func scheduleTimeBadge(_ event: OverviewEventSummary) -> TimeBadge? {
        let now = Date()
        let start = event.startDate
        let end = event.endDate
        if now >= start && now <= end {
            let mins = max(0, Int(end.timeIntervalSince(now) / 60))
            if mins > 60 {
                let h = mins / 60; let m = mins % 60
                return TimeBadge(text: m > 0 ? "\(h)h \(m)m left" : "\(h)h left",
                                 textColor: Color(hex: "059669"), bgColor: Color(hex: "D1FAE5"))
            }
            return TimeBadge(text: mins > 0 ? "\(mins)m left" : "Ending",
                             textColor: Color(hex: "059669"), bgColor: Color(hex: "D1FAE5"))
        } else if start > now {
            let mins = Int(start.timeIntervalSince(now) / 60)
            if mins < 60 {
                return TimeBadge(text: "in \(mins)m",
                                 textColor: Color(hex: "6366F1"), bgColor: Color(hex: "EEF2FF"))
            }
            let h = mins / 60; let m = mins % 60
            return TimeBadge(text: m > 0 ? "in \(h)h \(m)m" : "in \(h)h",
                             textColor: Color(hex: "6366F1"), bgColor: Color(hex: "EEF2FF"))
        }
        return nil
    }

    private func scheduleEventRow(_ event: OverviewEventSummary) -> some View {
        let isNow: Bool = {
            let now = Date()
            return now >= event.startDate && now <= event.endDate
        }()
        let f1 = DateFormatter(); f1.dateFormat = "hh:mm"
        let f2 = DateFormatter(); f2.dateFormat = "a"
        let timeStr = f1.string(from: event.startDate)
        let periodStr = f2.string(from: event.startDate)
        let badge = scheduleTimeBadge(event)

        return HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(timeStr).font(.system(size: 11, weight: .bold))
                    .foregroundColor(isNow ? Color(hex: "6366F1") : DesignSystem.Colors.textLight)
                Text(periodStr).font(.system(size: 9))
                    .foregroundColor(isNow ? Color(hex: "6366F1") : DesignSystem.Colors.textLight)
            }
            .frame(width: 48, height: 48)
            .background(isNow ? Color(hex: "EEF2FF") : Color(hex: "F9FAFB"))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "location")
                        .font(.system(size: 10)).foregroundColor(DesignSystem.Colors.textLight).lineLimit(1)
                }
            }
            Spacer()
            if let badge {
                Text(badge.text).font(.system(size: 10, weight: .bold))
                    .foregroundColor(badge.textColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badge.bgColor).clipShape(Capsule())
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.bgMain.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dayOfWeekLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: Date())
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "schedule",
            displayName:   "Today's Schedule",
            description:   "Your classes and events for today with live countdown badges.",
            category:      .academic,
            iconName:      "calendar.day.timeline.left",
            accentColor:   Color(hex: "10B981"),
            defaultHeight: 190,
            minHeight:     150,
            makePreview: { ScheduleWidgetPreview() }
        )
    }
}

// MARK: - Preview

private struct ScheduleWidgetPreview: View {
    private let events: [(String, String, String)] = [
        ("09:30", "AM", "CSE 312 — Algorithms"),
        ("11:00", "AM", "MTH 309 — Linear Algebra"),
        ("02:00", "PM", "EE 202 — Circuits Lab"),
    ]
    var body: some View {
        OverviewCard {
            Text("Today's Schedule")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(DesignSystem.Colors.textMain).padding(.bottom, 10)
            VStack(spacing: 6) {
                ForEach(events, id: \.0) { time, period, title in
                    HStack(spacing: 10) {
                        VStack(spacing: 1) {
                            Text(time).font(.system(size: 10, weight: .bold)).foregroundColor(DesignSystem.Colors.textLight)
                            Text(period).font(.system(size: 8)).foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .frame(width: 40, height: 40).background(Color(hex: "F9FAFB"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(title).font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                    }
                    .padding(8).background(DesignSystem.Colors.bgMain.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
