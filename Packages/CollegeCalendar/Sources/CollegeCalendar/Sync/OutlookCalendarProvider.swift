// OutlookCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — OutlookCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

public actor OutlookCalendarProvider: CalendarSyncProvider {
    public let id: CalendarSyncProviderID = .outlook

    public func connect() async throws {
        await MainActor.run { CalendarIntegrationBridge.manager?.connectOutlook() }
    }

    public func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectOutlook() }
    }

    public func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performOutlookSync(showNotifications: showNotifications)
    }

    public func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            manager.exportEventToOutlook(event)
        }
    }

    public func deleteRemoteEvent(localEventID: UUID) async throws {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.deleteEventFromOutlook(localEventID: localEventID)
    }
}
