// iCloudCalendarProvider.swift
// Feature: Calendar
// Purpose: Calendar module — iCloudCalendarProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor iCloudCalendarProvider: CalendarSyncProvider {
    let id: CalendarSyncProviderID = .icloud

    func connect() async throws {
        // Credentials supplied via settings UI — connectiCloud(username:password:)
    }

    func disconnect() async {
        await MainActor.run { CalendarIntegrationBridge.manager?.disconnectiCloud() }
    }

    func sync(showNotifications: Bool) async {
        guard let manager = await MainActor.run(body: { CalendarIntegrationBridge.manager }) else { return }
        await manager.performiCloudSync(showNotifications: showNotifications)
    }

    func exportEvent(eventID: UUID) async throws {
        // Phase 2b: CalDAV export.
    }

    func deleteRemoteEvent(localEventID: UUID) async throws {
        // CalDAV delete — Phase 2b.
    }
}
