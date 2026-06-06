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
        // Phase 2b: CalDAV export.
    }

    public func deleteRemoteEvent(localEventID: UUID) async throws {
        // CalDAV delete — Phase 2b.
    }
}
