// AppleCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncProviderError.
// Data: CollegePersistence / repositories when applicable.

import EventKit
import Foundation

/// EventKit sync provider — all `EKEventStore` work stays on this actor executor.
actor AppleCalendarProvider: CalendarSyncProvider {
    let id: CalendarSyncProviderID = .apple
    private let eventStore = EKEventStore()

    func connect() async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.connectAppleCalendar()
        }
    }

    func disconnect() async {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.disconnectAppleCalendar()
        }
    }

    func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performAppleSync(showNotifications: showNotifications)
    }

    func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToAppleCalendar(event)
        }
    }

    func deleteRemoteEvent(localEventID: UUID) async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.deleteEventFromAppleCalendar(localEventID: localEventID)
        }
    }
}

enum CalendarSyncProviderError: Error {
    case missingEvent
}
