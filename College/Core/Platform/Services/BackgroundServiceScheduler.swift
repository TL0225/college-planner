// BackgroundServiceScheduler.swift
// Feature: Core/Platform
// Purpose: Shared NSBackgroundActivityScheduler wrapper with completion contract.

import Foundation
import os

@MainActor
final class BackgroundServiceScheduler {
    private var scheduler: NSBackgroundActivityScheduler?
    private let identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }

    func configure(
        repeats: Bool,
        interval: TimeInterval,
        tolerance: TimeInterval,
        qualityOfService: QualityOfService = .utility
    ) {
        stop()
        let activity = NSBackgroundActivityScheduler(identifier: identifier)
        activity.repeats = repeats
        activity.interval = interval
        activity.tolerance = tolerance
        activity.qualityOfService = qualityOfService
        scheduler = activity
    }

    /// Schedules work. Handler runs off main; hop to MainActor for UI-only updates.
    func start(
        handler: @escaping @Sendable (_ completion: @escaping @Sendable (NSBackgroundActivityScheduler.Result) -> Void) async -> Void
    ) {
        guard let scheduler else { return }
        scheduler.schedule { completion in
            Task {
                let completionGate = CompletionOnce(completion: completion)
                await handler(completionGate.finish)
                completionGate.finish(.finished)
            }
        }
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
    }

    func invalidate() {
        stop()
    }
}

private final class CompletionOnce: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    private let completion: @Sendable (NSBackgroundActivityScheduler.Result) -> Void

    init(completion: @escaping @Sendable (NSBackgroundActivityScheduler.Result) -> Void) {
        self.completion = completion
    }

    func finish(_ result: NSBackgroundActivityScheduler.Result) {
        let shouldComplete = lock.withLock { didComplete -> Bool in
            guard !didComplete else { return false }
            didComplete = true
            return true
        }
        guard shouldComplete else { return }
        completion(result)
    }
}
