// CalendarProviderBackgroundSyncScheduler.swift
// Feature: Calendar
// Purpose: Registry-owned Google/Outlook/iCloud polling via BackgroundServiceScheduler.

import CollegeCalendar
import Foundation

@MainActor
final class CalendarProviderBackgroundSyncScheduler {
    static let shared = CalendarProviderBackgroundSyncScheduler()

    private let googleScheduler = BackgroundServiceScheduler(
        identifier: BackgroundServiceSchedulerIDs.calendarGoogleProviderSync
    )
    private let outlookScheduler = BackgroundServiceScheduler(
        identifier: BackgroundServiceSchedulerIDs.calendarOutlookProviderSync
    )
    private let iCloudScheduler = BackgroundServiceScheduler(
        identifier: BackgroundServiceSchedulerIDs.calendarICloudProviderSync
    )

    private init() {}

    func startGoogle() {
        googleScheduler.configure(repeats: true, interval: 60, tolerance: 10)
        googleScheduler.start { [weak self] completion in
            await self?.pollGoogle()
            completion(.finished)
        }
    }

    func stopGoogle() {
        googleScheduler.stop()
    }

    func startOutlook() {
        outlookScheduler.configure(repeats: true, interval: 60, tolerance: 10)
        outlookScheduler.start { [weak self] completion in
            await self?.pollOutlook()
            completion(.finished)
        }
    }

    func stopOutlook() {
        outlookScheduler.stop()
    }

    func startICloud() {
        iCloudScheduler.configure(repeats: true, interval: 120, tolerance: 15)
        iCloudScheduler.start { [weak self] completion in
            await self?.pollICloud()
            completion(.finished)
        }
    }

    func stopICloud() {
        iCloudScheduler.stop()
    }

    func stopAll() {
        stopGoogle()
        stopOutlook()
        stopICloud()
    }

    private func pollGoogle() async {
        guard CalendarIntegrationBridge.manager?.googleStatus == .connected else { return }
        await CalendarIntegrationBridge.manager?.performGoogleSync(showNotifications: false)
    }

    private func pollOutlook() async {
        guard CalendarIntegrationBridge.manager?.outlookStatus == .connected else { return }
        await CalendarIntegrationBridge.manager?.performOutlookSync(showNotifications: false)
    }

    private func pollICloud() async {
        guard CalendarIntegrationBridge.manager?.iCloudStatus == .connected else { return }
        await CalendarIntegrationBridge.manager?.performiCloudSync(showNotifications: false)
    }
}
