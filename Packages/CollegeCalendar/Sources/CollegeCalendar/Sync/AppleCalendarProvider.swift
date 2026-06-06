// AppleCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncProviderError.
// Data: CollegePersistence / repositories when applicable.

import EventKit
import Foundation

/// EventKit sync provider — all `EKEventStore` work stays on this actor executor.
public actor AppleCalendarProvider: CalendarSyncProvider {
    public let id: CalendarSyncProviderID = .apple
    private let eventStore = EKEventStore()

    public func connect() async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.connectAppleCalendar()
        }
    }

    public func disconnect() async {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.disconnectAppleCalendar()
        }
    }

    public func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performAppleSync(showNotifications: showNotifications)
    }

    public func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToAppleCalendar(event)
        }
    }

    public func deleteRemoteEvent(localEventID: UUID) async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.deleteEventFromAppleCalendar(localEventID: localEventID)
        }
    }
}
