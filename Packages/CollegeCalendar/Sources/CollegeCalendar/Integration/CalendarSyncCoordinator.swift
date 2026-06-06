// CalendarSyncCoordinator.swift
// Feature: Calendar
// Purpose: Routes calendar sync/export to per-provider actor implementations.

import Foundation

/// Routes calendar sync/export to per-provider `actor` implementations (Phase 2b facade).
@MainActor
public enum CalendarSyncCoordinator {
    public static let apple = AppleCalendarProvider()
    public static let google = GoogleCalendarProvider()
    public static let outlook = OutlookCalendarProvider()
    public static let iCloud = iCloudCalendarProvider()

    public static func exportAfterWrite(
        eventID: UUID,
        options: CalendarEventWriteOptions,
        manager: CalendarIntegrationManager
    ) async {
        guard let event = CalendarSyncEventResolver.calendarEvent(for: eventID) else {
            return
        }

        if let googleID = options.exportGoogleCalendarID, !googleID.isEmpty {
            if manager.googleStatus == .connected {
                manager.exportEventToGoogle(event, targetCalendarID: googleID)
            }
        } else if manager.googleStatus == .connected {
            manager.exportEventToGoogle(event)
        }

        if manager.appleStatus == .connected {
            manager.exportEventToAppleCalendar(event)
        }

        if manager.outlookStatus == .connected {
            manager.exportEventToOutlook(event)
        }
    }

    public static func syncAll(showNotifications: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await apple.sync(showNotifications: showNotifications) }
            group.addTask { await google.sync(showNotifications: showNotifications) }
            group.addTask { await outlook.sync(showNotifications: showNotifications) }
            group.addTask { await iCloud.sync(showNotifications: showNotifications) }
        }
    }
}
