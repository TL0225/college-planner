// GoogleCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — GoogleCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor GoogleCalendarProvider: CalendarSyncProvider {
    let id: CalendarSyncProviderID = .google

    func connect() async throws {
        await MainActor.run { CalendarIntegrationBridge.manager?.connectGoogle() }
    }

    func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectGoogle() }
    }

    func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performGoogleSync(showNotifications: showNotifications)
    }

    func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToGoogle(event)
        }
    }

    func deleteRemoteEvent(localEventID: UUID) async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.deleteEventFromGoogle(localEventID: localEventID)
        }
    }
}
