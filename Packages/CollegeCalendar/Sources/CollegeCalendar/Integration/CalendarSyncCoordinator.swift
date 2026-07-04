// CalendarSyncCoordinator.swift
// Feature: Calendar
// Purpose: Routes calendar sync/export to per-provider actor implementations.

import Foundation

public struct CalendarExportAfterWriteResult: Sendable {
    public var google: Bool?
    public var apple: Bool?
    public var outlook: Bool?
    public var iCloud: Bool?
    public var attemptedGuestInvites: Bool
    public var guestInvitesSucceeded: Bool?

    public var allSucceeded: Bool {
        let outcomes = [google, apple, outlook, iCloud].compactMap { $0 }
        let providerOK = outcomes.isEmpty || outcomes.allSatisfy { $0 }
        if attemptedGuestInvites, let guestInvitesSucceeded {
            return providerOK && guestInvitesSucceeded
        }
        return providerOK
    }

    public init(
        google: Bool? = nil,
        apple: Bool? = nil,
        outlook: Bool? = nil,
        iCloud: Bool? = nil,
        attemptedGuestInvites: Bool = false,
        guestInvitesSucceeded: Bool? = nil
    ) {
        self.google = google
        self.apple = apple
        self.outlook = outlook
        self.iCloud = iCloud
        self.attemptedGuestInvites = attemptedGuestInvites
        self.guestInvitesSucceeded = guestInvitesSucceeded
    }
}

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
    ) async -> CalendarExportAfterWriteResult {
        guard let event = CalendarSyncEventResolver.calendarEvent(for: eventID) else {
            return CalendarExportAfterWriteResult()
        }

        var googleResult: Bool?
        var appleResult: Bool?
        var outlookResult: Bool?
        var iCloudResult: Bool?

        if let googleID = options.exportGoogleCalendarID, !googleID.isEmpty {
            if manager.googleStatus == .connected {
                googleResult = await manager.exportEventToGoogleAsync(
                    event,
                    targetCalendarID: googleID
                )
            }
        } else if manager.googleStatus == .connected {
            googleResult = await manager.exportEventToGoogleAsync(event)
        }

        if manager.appleStatus == .connected {
            appleResult = await manager.exportEventToAppleCalendarAsync(
                event,
                calendarName: options.exportAppleCalendarName
            )
        }

        if manager.outlookStatus == .connected {
            outlookResult = await manager.exportEventToOutlookAsync(event)
        }

        if manager.iCloudStatus == .connected {
            iCloudResult = await manager.exportEventToiCloudAsync(event)
        }

        let attemptedGuestInvites = CalendarGuestInviteExporter.hasInviteRecipients(in: event.attendeesJSON)
        let guestInviteOutcomes = [googleResult, outlookResult, iCloudResult].compactMap { $0 }
        let guestInvitesSucceeded: Bool? = attemptedGuestInvites
            ? (!guestInviteOutcomes.isEmpty && guestInviteOutcomes.allSatisfy { $0 })
            : nil

        return CalendarExportAfterWriteResult(
            google: googleResult,
            apple: appleResult,
            outlook: outlookResult,
            iCloud: iCloudResult,
            attemptedGuestInvites: attemptedGuestInvites,
            guestInvitesSucceeded: guestInvitesSucceeded
        )
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
