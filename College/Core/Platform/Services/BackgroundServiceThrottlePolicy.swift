// BackgroundServiceThrottlePolicy.swift
// Feature: Core/Platform
// Purpose: How services respond to app inactive throttling.

import Foundation

enum BackgroundServiceThrottlePolicy: Sendable, Equatable {
    /// Pause when `AppActivityCoordinator.isResourceThrottled` is true.
    case pauseWhenInactive
    /// Skip starting while throttled; retry when active.
    case deferUntilActive
    /// Keep running regardless of inactive dim policy.
    case alwaysRun
}
