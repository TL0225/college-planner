// StartupPhase.swift
// Feature: App
// Purpose: App module — StartupPhase.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// High-level launch lifecycle for gating deferred work and diagnostics.
enum StartupPhase: String, Sendable, Equatable {
    case idle
    case boot
    case storeReady
    case snapshotsWarm
    case integrationsWarm
    case featuresWarm
    /// Preload pipeline finished; UI phases begin when main content appears.
    case completed
    /// Main window/content is on-screen (post-preload).
    case firstFrameReady
    /// Staggered deferred startup jobs are running (model bootstrap, monitors, linker, …).
    case deferredWarmup
    /// Deferred jobs have had time to finish; steady operation.
    case steadyState
}
