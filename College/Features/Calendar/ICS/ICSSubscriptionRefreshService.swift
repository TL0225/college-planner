// ICSSubscriptionRefreshService.swift
// Feature: Calendar
// Purpose: Calendar module — ICSSubscriptionRefreshService.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Foundation

/// Refreshes ICS subscription feeds on macOS (Phase 4). Uses `NSBackgroundActivityScheduler`, not BGTaskScheduler.
@MainActor
final class ICSSubscriptionRefreshService {
    static let shared = ICSSubscriptionRefreshService()

    private var scheduler: NSBackgroundActivityScheduler?
    private var becameActiveObserver: NSObjectProtocol?

    private static let networkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

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
        scheduler?.invalidate()
        scheduler = nil
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
        guard let url = URL(string: subscription.urlString) else { return }
        do {
            let (data, _) = try await Self.networkSession.data(from: url)
            let events = try ICSCalendarParser.parse(data: data)
            await ICSSubscriptionUpsertService.upsert(
                events: events,
                subscriptionID: UUID(uuidString: subscription.id) ?? UUID(),
                sourceURL: subscription.urlString
            )
        } catch {
            #if DEBUG
            print("[ICSSubscriptionRefresh] \(reason) failed \(subscription.name): \(error)")
            #endif
        }
    }

    private func registerBackgroundScheduler() {
        let activity = NSBackgroundActivityScheduler(identifier: "com.college.calendar.ics-refresh")
        activity.repeats = true
        activity.interval = 60 * 60
        activity.qualityOfService = .utility
        activity.tolerance = 15 * 60
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.refreshAll(reason: .backgroundScheduler)
                completion(.finished)
            }
        }
        scheduler = activity
    }

    enum RefreshReason: String {
        case appBecameActive
        case backgroundScheduler
        case calendarAppear
        case manual
    }
}
