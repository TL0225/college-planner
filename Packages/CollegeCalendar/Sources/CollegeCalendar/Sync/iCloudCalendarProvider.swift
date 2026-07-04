// iCloudCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — iCloudCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

public actor iCloudCalendarProvider: CalendarSyncProvider {
    public let id: CalendarSyncProviderID = .icloud

    public func connect() async throws {
        // Credentials supplied via settings UI — connectiCloud(username:password:)
    }

    public func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectiCloud() }
    }

    public func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performiCloudSync(showNotifications: showNotifications)
    }

    public func exportEvent(eventID: UUID) async throws {
        try await MainActor.run {
            guard let manager = CalendarIntegrationBridge.manager,
                  let event = CalendarSyncEventResolver.calendarEvent(for: eventID)
            else {
                throw CalendarSyncProviderError.missingEvent
            }
            Task { await manager.exportEventToiCloudAsync(event) }
        }
    }

    public func deleteRemoteEvent(localEventID: UUID) async throws {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.deleteEventFromiCloud(localEventID: localEventID)
    }
}
