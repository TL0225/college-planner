// GoogleCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — GoogleCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

public actor GoogleCalendarProvider: CalendarSyncProvider {
    public let id: CalendarSyncProviderID = .google

    public func connect() async throws {
        await MainActor.run { CalendarIntegrationBridge.manager?.connectGoogle() }
    }

    public func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectGoogle() }
    }

    public func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performGoogleSync(showNotifications: showNotifications)
    }

    public func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToGoogle(event)
        }
    }

    public func deleteRemoteEvent(localEventID: UUID) async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.deleteEventFromGoogle(localEventID: localEventID)
        }
    }
}
