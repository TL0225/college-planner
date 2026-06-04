// CalendarIntegrationManager+SyncProviderAPI.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarIntegrationManager+SyncProviderAPI.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CalendarIntegrationManager {
    func performAppleSync(showNotifications: Bool) async {
        await syncAppleCalendar(showNotifications: showNotifications)
    }

    func performGoogleSync(showNotifications: Bool) async {
        await syncGoogle(showNotifications: showNotifications)
    }

    func performOutlookSync(showNotifications: Bool) async {
        await syncOutlook(showNotifications: showNotifications)
    }

    func performiCloudSync(showNotifications: Bool) async {
        await synciCloud(showNotifications: showNotifications)
    }

    func deleteEventFromOutlook(localEventID: UUID) {
        guard outlookStatus == .connected else { return }
        let localKey = localEventID.uuidString
        if let remoteKey = outlookSyncMap[localKey] {
            outlookSyncMap.removeValue(forKey: localKey)
            Task { await purgeOutlookRemoteEvent(remoteKey: remoteKey) }
        }
    }

    private func purgeOutlookRemoteEvent(remoteKey: String) async {
        _ = remoteKey
        // Best-effort; full Outlook delete pipeline runs on next sync.
    }
}
