// CalendarTimeEntryParser.swift
// Feature: Calendar
// Purpose: Parse typed hour:minute strings for calendar time fields.

import Foundation

public enum CalendarTimeEntryParser {
    /// Applies a typed time such as `9:05`, `09:05`, or `21:30` onto the calendar day of `selection`.
    public static func date(
        byApplying timeText: String,
        to selection: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let minute = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selection)
    }
}
