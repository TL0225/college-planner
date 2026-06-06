// CalendarReminderScheduler.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarReminderInfo.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import UserNotifications

// MARK: - CalendarReminderScheduler
//
// Schedules and cancels macOS UNUserNotificationCenter reminders for calendar events.
// Uses the event UUID as the notification identifier prefix so reminders can be
// cancelled individually when an event is edited or deleted.

public final class CalendarReminderScheduler: @unchecked Sendable {

    // MARK: Singleton

    public static let shared = CalendarReminderScheduler()
    private init() {}

    // MARK: - Authorization

    /// Requests UNUserNotificationCenter permission if not already granted.
    /// Call once at app launch (best placed in AppDelegate / @main).
    public func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if let error {
                print("[CalendarReminderScheduler] Authorization error: \(error.localizedDescription)")
            } else {
                print("[CalendarReminderScheduler] Notification permission granted: \(granted)")
            }
            #endif
        }
    }

    // MARK: - Schedule

    /// Schedules OS-level reminder notifications for an event.
    ///
    /// - Parameters:
    ///   - eventID:      The local UUID of the calendar event.
    ///   - title:        Event title displayed in the notification.
    ///   - startDate:    Event start time.
    ///   - leadMinutes:  Array of lead times (in minutes before start) at which to fire.
    ///                   Defaults to the user's default reminder setting.
    ///   - conferenceURL: Optional join link surfaced as an action button.
    public func schedule(
        eventID: UUID,
        title: String,
        startDate: Date,
        leadMinutes: [Int]? = nil,
        conferenceURL: String? = nil
    ) {
        let leads = leadMinutes ?? defaultLeadMinutes
        guard !leads.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        for minutes in leads {
            let fireDate = startDate.addingTimeInterval(-Double(minutes) * 60)
            guard fireDate > Date() else { continue }   // Don't schedule past notifications.

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = reminderBody(leadMinutes: minutes, startDate: startDate)
            content.sound = .default
            content.categoryIdentifier = "CALENDAR_EVENT_REMINDER"

            if let urlStr = conferenceURL, !urlStr.isEmpty {
                content.userInfo = ["conferenceURL": urlStr, "eventID": eventID.uuidString]
            } else {
                content.userInfo = ["eventID": eventID.uuidString]
            }

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let requestID = notificationID(eventID: eventID, leadMinutes: minutes)
            let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)

            center.add(request) { error in
                #if DEBUG
                if let error {
                    print("[CalendarReminderScheduler] Failed to schedule '\(title)' -\(minutes)min: \(error.localizedDescription)")
                }
                #endif
            }
        }
    }

    // MARK: - Cancel

    /// Cancels all pending reminders for a given event.
    ///
    /// Uses deterministic ID construction instead of `getPendingNotificationRequests` to
    /// avoid an expensive XPC round-trip that scans *all* pending notifications.
    public func cancelReminders(eventID: UUID) {
        cancel(eventID: eventID)
    }

    public func isCalendarMuted(for event: CalendarStoredEvent) -> Bool {
        _ = event
        return false
    }

    public func cancel(eventID: UUID) {
        let center = UNUserNotificationCenter.current()
        // Enumerate every lead-time variant we may have ever scheduled and remove them all.
        // removePendingNotificationRequests silently ignores IDs that don't exist.
        let knownLeadMinutes = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 240]
        let ids = knownLeadMinutes.map { notificationID(eventID: eventID, leadMinutes: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels old reminders for an event and reschedules with new parameters.
    public func reschedule(
        eventID: UUID,
        title: String,
        startDate: Date,
        leadMinutes: [Int]? = nil,
        conferenceURL: String? = nil
    ) {
        cancel(eventID: eventID)
        schedule(
            eventID: eventID,
            title: title,
            startDate: startDate,
            leadMinutes: leadMinutes,
            conferenceURL: conferenceURL
        )
    }

    // MARK: - Batch (sync import)

    /// Schedules reminders for a batch of events imported from a sync source.
    /// Only schedules events in the future; silently skips past events.
    public func scheduleBatch(events: [CalendarReminderInfo]) {
        for info in events {
            guard info.startDate > Date() else { continue }
            schedule(
                eventID: info.eventID,
                title: info.title,
                startDate: info.startDate,
                leadMinutes: info.leadMinutes,
                conferenceURL: info.conferenceURL
            )
        }
    }

    // MARK: - Register Notification Category (call at launch)

    /// Registers the calendar reminder UNNotificationCategory with actionable buttons.
    public func registerNotificationCategories() {
        var actions: [UNNotificationAction] = [
            UNNotificationAction(
                identifier: "SNOOZE_10",
                title: "Snooze 10 min",
                options: []
            ),
            UNNotificationAction(
                identifier: "MARK_DONE",
                title: "Mark Done",
                options: [.destructive]
            )
        ]

        // Only add "Join Meeting" if we have a conference URL (checked at delivery time via userInfo).
        let joinAction = UNNotificationAction(
            identifier: "JOIN_MEETING",
            title: "Join Meeting",
            options: [.foreground]
        )
        actions.insert(joinAction, at: 0)

        let category = UNNotificationCategory(
            identifier: "CALENDAR_EVENT_REMINDER",
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Private Helpers

    private var defaultLeadMinutes: [Int] {
        let stored = UserDefaults.standard.integer(forKey: "calendar.defaultReminderMinutes")
        return stored > 0 ? [stored] : [15]
    }

    private func notificationID(eventID: UUID, leadMinutes: Int) -> String {
        "college.event.\(eventID.uuidString).reminder.\(leadMinutes)"
    }

    private func reminderBody(leadMinutes: Int, startDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeStr = formatter.string(from: startDate)
        if leadMinutes == 0 { return "Starting now (\(timeStr))" }
        if leadMinutes < 60 { return "Starting in \(leadMinutes) min at \(timeStr)" }
        let hours = leadMinutes / 60
        return "Starting in \(hours) hour\(hours == 1 ? "" : "s") at \(timeStr)"
    }
}

// MARK: - CalendarReminderInfo

public struct CalendarReminderInfo: Sendable {
    public let eventID: UUID
    public let title: String
    public let startDate: Date
    public let leadMinutes: [Int]?
    public let conferenceURL: String?

    public init(
        eventID: UUID,
        title: String,
        startDate: Date,
        leadMinutes: [Int]?,
        conferenceURL: String?
    ) {
        self.eventID = eventID
        self.title = title
        self.startDate = startDate
        self.leadMinutes = leadMinutes
        self.conferenceURL = conferenceURL
    }
}
