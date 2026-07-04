// CalendarProviderSyncBridge.swift
// Feature: Calendar
// Purpose: Registry-aware calendar provider loop start after OAuth connect.

import CollegeCalendar
import Foundation

@MainActor
enum CalendarProviderSyncBridge {
    static func wireIntegrationBridge() {
        CalendarIntegrationBridge.onProviderConnected = {
            handleProviderConnected()
        }
        let scheduler = CalendarProviderBackgroundSyncScheduler.shared
        CalendarIntegrationBridge.startGoogleProviderPolling = { scheduler.startGoogle() }
        CalendarIntegrationBridge.stopGoogleProviderPolling = { scheduler.stopGoogle() }
        CalendarIntegrationBridge.startOutlookProviderPolling = { scheduler.startOutlook() }
        CalendarIntegrationBridge.stopOutlookProviderPolling = { scheduler.stopOutlook() }
        CalendarIntegrationBridge.startICloudProviderPolling = { scheduler.startICloud() }
        CalendarIntegrationBridge.stopICloudProviderPolling = { scheduler.stopICloud() }
    }

    static func handleProviderConnected() {
        guard BackgroundServiceRegistry.shared.isSceneActive(.calendar) else { return }
        CalendarIntegrationBridge.manager?.startProviderBackgroundSyncLoops()
    }
}
