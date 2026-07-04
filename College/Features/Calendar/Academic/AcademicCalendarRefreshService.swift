// AcademicCalendarRefreshService.swift
// Feature: Calendar
// Purpose: Background refresh for academic calendar imports.

import AppKit
import Foundation
import UserNotifications

@MainActor
final class AcademicCalendarRefreshService {
    static let shared = AcademicCalendarRefreshService()

    private let scheduler = BackgroundServiceScheduler(identifier: BackgroundServiceSchedulerIDs.academicCalendarRefresh)
    private var becameActiveObserver: NSObjectProtocol?

    private init() {}

    func start() {
        registerBackgroundScheduler()
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refreshAll(reason: .appBecameActive) }
        }
    }

    func stop() {
        scheduler.invalidate()
        if let becameActiveObserver {
            NotificationCenter.default.removeObserver(becameActiveObserver)
        }
    }

    func refreshAll(reason: RefreshReason) async {
        let persistence = CollegePersistence.shared
        let configs = AcademicCalendarSyncEligibility.eligibleConfigs(persistence: persistence)
        guard !configs.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for config in configs {
                group.addTask { [self] in
                    try? Task.checkCancellation()
                    await self.refreshConfig(config, reason: reason)
                }
            }
        }
    }

    private func refreshConfig(_ config: AcademicCalendarConfig, reason: RefreshReason) async {
        var config = config
        if shouldReResolveHub(config: config, persistence: CollegePersistence.shared) {
            config.chosenSubCalendarURL = nil
            config.importedScopes = AcademicCalendarTermScope.importedScopes(
                persistence: CollegePersistence.shared,
                level: config.levelScope
            )
            config.importStatus = .resolving
            AcademicCalendarStore.upsertConfig(config)
        }

        let activityID = BackgroundActivityCenter.academicCalendarActivityID(configID: config.configID)
        BackgroundActivityReporter.running(
            id: activityID,
            domain: .academicCalendar,
            title: config.calendarDisplayName,
            detail: String(localized: "calendar.background.scraping", defaultValue: "Refreshing academic calendar…"),
            indeterminate: true
        )

        let profile = AcademicCalendarProgramProfile.resolve(persistence: CollegePersistence.shared)
        let output = await AcademicCalendarScrapeService.scrape(
            config: &config,
            reason: .background,
            writeChanges: true,
            programProfile: profile
        )

        let summary: String
        if output.result.totalDelta > 0 {
            summary = String(
                format: String(localized: "calendar.background.updated", defaultValue: "%d event(s) updated"),
                output.result.totalDelta
            )
            postDiffNotification(config: config, result: output.result)
        } else if output.contentUnchanged {
            summary = String(localized: "calendar.background.unchanged", defaultValue: "Calendar up to date")
        } else {
            summary = String(localized: "calendar.background.refreshed", defaultValue: "Calendar refreshed")
        }

        BackgroundActivityReporter.finish(
            id: activityID,
            succeeded: output.result.error == nil,
            summary: output.result.error ?? summary
        )
        _ = reason
    }

    private func postDiffNotification(config: AcademicCalendarConfig, result: AcademicCalendarSyncResult) {
        let count = result.totalDelta
        let content = UNMutableNotificationContent()
        content.title = "\(config.calendarDisplayName) updated"
        content.body = "\(count) event(s) changed since last scrape."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func registerBackgroundScheduler() {
        scheduler.configure(
            repeats: true,
            interval: 24 * 60 * 60,
            tolerance: 60 * 60,
            qualityOfService: .utility
        )
        scheduler.start { [weak self] completion in
            await self?.refreshAll(reason: .backgroundScheduler)
            completion(.finished)
        }
    }

    enum RefreshReason: String {
        case appBecameActive
        case backgroundScheduler
        case manual
    }

    private func shouldReResolveHub(config: AcademicCalendarConfig, persistence: CollegePersistence) -> Bool {
        guard let scope = AcademicCalendarTermScope.resolve(persistence: persistence, level: config.levelScope) else {
            return false
        }
        let currentScope = config.importedScopes.first
        guard let currentScope else { return false }
        if currentScope.term != scope.term || currentScope.year != scope.year {
            return true
        }
        if config.lastSuccessfulEventCount > 0,
           config.lastSuccessfulEventCount < AcademicCalendarLinkValidator.dynamicEventThreshold(for: currentScope) {
            return true
        }
        return false
    }
}
