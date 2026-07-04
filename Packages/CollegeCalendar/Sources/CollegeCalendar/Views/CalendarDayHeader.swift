// CalendarDayHeader.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTimeZoneCornerLabel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Top-left corner of the week/day timed grid (above hour labels).
struct CalendarTimeZoneCornerLabel: View {
    let timeZone: TimeZone
    var referenceDate: Date = Date()

    private var abbreviation: String {
        if let abbr = timeZone.abbreviation(for: referenceDate), !abbr.isEmpty {
            return abbr
        }
        let title = CalendarTimeZonePreference.displayTitle(for: timeZone)
        if title.count <= 6 {
            return title
        }
        return CalendarTimeZonePreference.gmtOffsetStamp(referenceDate, timeZone: timeZone)
    }

    private var detail: String {
        CalendarTimeZonePreference.gmtOffsetStamp(referenceDate, timeZone: timeZone)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(abbreviation)
                .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
        .padding(.top, 14)
    }
}

/// Month-style day number badge (13pt in 24px circle, accent when today).
struct CalendarDayHeader: View {
    let dayNumber: Int
    let isCurrentDay: Bool
    var eventsEmpty: Bool = false
    /// Day view: center the badge under the weekday label; week/month cells stay leading-aligned.
    var centersInColumn: Bool = false

    @State private var isHovered = false

    var body: some View {
        Group {
            if centersInColumn {
                dayNumberBadge
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack {
                    dayNumberBadge
                    Spacer()
                }
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 6)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var dayNumberBadge: some View {
        if isCurrentDay {
            Text("\(dayNumber)")
                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(isHovered ? 0.5 : 0), radius: 6)
        } else {
            Text("\(dayNumber)")
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(eventsEmpty ? Color.secondary.opacity(0.55) : Color.primary.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                .clipShape(Circle())
                .padding(.leading, centersInColumn ? 0 : 2)
                .padding(.top, centersInColumn ? 0 : 2)
        }
    }
}

/// Weekday label row matching `monthGridView` headers.
struct CalendarWeekdayHeaderRow: View {
    let dates: [Date]
    /// Day view: show full weekday name (e.g. TUESDAY) centered above the day number.
    var useFullWeekdayName: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dates, id: \.timeIntervalSince1970) { date in
                Text(weekdayLabel(for: date))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = useFullWeekdayName ? CalendarFormatters.weekdayFull : CalendarFormatters.weekday
        return formatter.string(from: date).uppercased()
    }
}
