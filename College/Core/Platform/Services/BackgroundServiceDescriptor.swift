// BackgroundServiceDescriptor.swift
// Feature: Core/Platform
// Purpose: Metadata + lifecycle hooks for a registered background service.

import Foundation

struct BackgroundServiceDescriptor: Sendable {
    let id: String
    let displayName: String
    let activityDomain: BackgroundActivityDomain?
    let activation: BackgroundServiceActivation
    let throttle: BackgroundServiceThrottlePolicy
    let resourceLane: LaunchStartupBudget.Lane?
    /// Lower starts first within the same activation phase.
    let sortOrder: Int

    let start: @MainActor @Sendable () async -> Void
    let stop: @MainActor @Sendable () async -> Void
    let pause: (@MainActor @Sendable () async -> Void)?
    let resume: (@MainActor @Sendable () async -> Void)?

    init(
        id: String,
        displayName: String,
        activityDomain: BackgroundActivityDomain? = nil,
        activation: BackgroundServiceActivation,
        throttle: BackgroundServiceThrottlePolicy = .alwaysRun,
        resourceLane: LaunchStartupBudget.Lane? = nil,
        sortOrder: Int = 0,
        start: @escaping @MainActor @Sendable () async -> Void,
        stop: @escaping @MainActor @Sendable () async -> Void,
        pause: (@MainActor @Sendable () async -> Void)? = nil,
        resume: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.activityDomain = activityDomain
        self.activation = activation
        self.throttle = throttle
        self.resourceLane = resourceLane
        self.sortOrder = sortOrder
        self.start = start
        self.stop = stop
        self.pause = pause
        self.resume = resume
    }
}
