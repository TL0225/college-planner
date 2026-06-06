// OutlookCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — OutlookCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor OutlookCalendarProvider: CalendarSyncProvider {
    let id: CalendarSyncProviderID = .outlook

    func connect() async throws {
        await MainActor.run { CalendarIntegrationBridge.manager?.connectOutlook() }
    }

    func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectOutlook() }
    }

    func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performOutlookSync(showNotifications: showNotifications)
    }

    func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToOutlook(event)
        }
    }

    func deleteRemoteEvent(localEventID: UUID) async throws {
        await MainActor.run {
            CalendarIntegrationBridge.manager?.deleteEventFromOutlook(localEventID: localEventID)
        }
    }
}
