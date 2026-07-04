// ICSSubscriptionRefreshService.swift
// Feature: Calendar
// Purpose: Calendar module — ICSSubscriptionRefreshService.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation
import CollegeCalendar

/// Refreshes ICS subscription feeds on macOS (Phase 4).
@MainActor
final class ICSSubscriptionRefreshService {
    static let shared = ICSSubscriptionRefreshService()

    private let backgroundScheduler = BackgroundServiceScheduler(
        identifier: BackgroundServiceSchedulerIDs.icsSubscriptionRefresh
    )
    private let fetcher = ICSFeedFetcher.shared
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
        backgroundScheduler.stop()
        if let becameActiveObserver {
            NotificationCenter.default.removeObserver(becameActiveObserver)
        }
    }

    func refreshAll(reason: RefreshReason) async {
        let subscriptions = ICSSubscription.loadAll()
        guard !subscriptions.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            let maxConcurrent = 4
            var iterator = subscriptions.makeIterator()

            func enqueueNext() {
                guard inFlight < maxConcurrent, let sub = iterator.next() else { return }
                inFlight += 1
                group.addTask { [self] in
                    await self.refresh(subscription: sub, reason: reason)
                }
            }

            for _ in 0..<min(maxConcurrent, subscriptions.count) { enqueueNext() }

            while await group.next() != nil {
                inFlight -= 1
                enqueueNext()
            }
        }
    }

    func refresh(subscription: ICSSubscription, reason: RefreshReason) async {
        let activityID = BackgroundActivityCenter.icsSubscriptionActivityID(subscriptionID: subscription.id)
        do {
            let events = try await fetcher.fetchEvents(
                urlString: subscription.urlString,
                feedKind: subscription.feedKind
            )
            await ICSSubscriptionUpsertService.upsert(
                events: events,
                subscriptionID: UUID(uuidString: subscription.id) ?? UUID(),
                sourceURL: subscription.urlString
            )
        } catch {
            BackgroundActivityReporter.finish(
                id: activityID,
                succeeded: false,
                summary: "\(subscription.name): \(error.localizedDescription)"
            )
            _ = reason
        }
    }

    private func registerBackgroundScheduler() {
        backgroundScheduler.configure(
            repeats: true,
            interval: 60 * 60,
            tolerance: 15 * 60
        )
        backgroundScheduler.start { [weak self] completion in
            await self?.refreshAll(reason: .backgroundScheduler)
            completion(.finished)
        }
    }

    enum RefreshReason: String {
        case appBecameActive
        case backgroundScheduler
        case calendarAppear
        case manual
    }
}
