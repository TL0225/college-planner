// CalendarSyncCoordinator.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Routes calendar sync/export to per-provider `actor` implementations (Phase 2b facade).
@MainActor
enum CalendarSyncCoordinator {
    static let apple = AppleCalendarProvider()
    static let google = GoogleCalendarProvider()
    static let outlook = OutlookCalendarProvider()
    static let iCloud = iCloudCalendarProvider()

    static func exportAfterWrite(
        eventID: UUID,
        options: CalendarEventWriteOptions,
        manager: CalendarIntegrationManager
    ) async {
        guard let event = try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: eventID) else {
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

    static func syncAll(showNotifications: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await apple.sync(showNotifications: showNotifications) }
            group.addTask { await google.sync(showNotifications: showNotifications) }
            group.addTask { await outlook.sync(showNotifications: showNotifications) }
            group.addTask { await iCloud.sync(showNotifications: showNotifications) }
        }
    }
}
