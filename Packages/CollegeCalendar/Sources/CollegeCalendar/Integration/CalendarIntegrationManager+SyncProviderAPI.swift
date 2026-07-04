// CalendarIntegrationManager+SyncProviderAPI.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarIntegrationManager+SyncProviderAPI.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CalendarIntegrationManager {
    public func performAppleSync(showNotifications: Bool) async {
        await syncAppleCalendar(showNotifications: showNotifications)
    }

    public func performGoogleSync(showNotifications: Bool) async {
        await syncGoogle(showNotifications: showNotifications)
    }

    public func performOutlookSync(showNotifications: Bool) async {
        await syncOutlook(showNotifications: showNotifications)
    }

    public func performiCloudSync(showNotifications: Bool) async {
        await synciCloud(showNotifications: showNotifications)
    }

    func deleteEventFromOutlook(localEventID: UUID) async {
        guard outlookStatus == .connected else { return }
        let localKey = localEventID.uuidString
        if let remoteKey = outlookRemoteKey(forLocalID: localKey) {
            var map = outlookSyncMap
            map.removeValue(forKey: remoteKey)
            outlookSyncMap = map
            await purgeOutlookRemoteEvent(remoteKey: remoteKey)
        }
    }

    func deleteEventFromiCloud(localEventID: UUID) async {
        guard iCloudStatus == .connected else { return }
        let localKey = localEventID.uuidString
        if let remoteKey = iCloudRemoteKey(forLocalID: localKey) {
            var map = iCloudSyncMap
            map.removeValue(forKey: remoteKey)
            iCloudSyncMap = map
            await purgeiCloudRemoteEvent(remoteKey: remoteKey)
        }
    }

    private func purgeOutlookRemoteEvent(remoteKey: String) async {
        do {
            let token = try await OutlookAuthService.shared.validAccessToken()
            guard let url = URL(string: "https://graph.microsoft.com/v1.0/me/events/\(remoteKey)") else {
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await secureSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
        } catch {
            // Best-effort; next sync reconciles.
        }
    }

    private func purgeiCloudRemoteEvent(remoteKey: String) async {
        guard let username = iCloudKeychainGet(iCloudUsernameKey),
              let password = iCloudKeychainGet(iCloudPasswordKey)
        else { return }

        let parts = remoteKey.split(separator: "||", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let calendarURL = URL(string: parts[0])
        else { return }

        let uid = parts[1]
        let eventURL = calendarURL.appendingPathComponent("\(uid).ics")
        var request = URLRequest(url: eventURL)
        request.httpMethod = "DELETE"
        addCalDAVAuth(&request, username: username, password: password)
        _ = try? await URLSession.shared.data(for: request)
    }
}
