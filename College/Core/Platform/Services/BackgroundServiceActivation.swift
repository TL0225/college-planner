// BackgroundServiceActivation.swift
// Feature: Core/Platform
// Purpose: When a background service should start.

import Foundation

/// Lifecycle activation phase for a registered background service.
enum BackgroundServiceActivation: Sendable, Equatable {
    case atLaunch
    case atMainUIReady
    case onSceneActive(AppPage)
    case onDemand

    func matches(bootstrap: BackgroundServiceBootstrapPhase, activePage: AppPage?) -> Bool {
        switch (self, bootstrap) {
        case (.atLaunch, .atLaunch):
            return true
        case (.atMainUIReady, .atMainUIReady):
            return true
        case (.onSceneActive(let page), .onSceneActive(let active)):
            return page == active
        case (.onDemand, _):
            return false
        default:
            return false
        }
    }

    func matchesScene(_ page: AppPage) -> Bool {
        if case .onSceneActive(let expected) = self {
            return expected == page
        }
        return false
    }
}

/// Registry bootstrap entry points.
enum BackgroundServiceBootstrapPhase: Sendable, Equatable {
    case atLaunch
    case atMainUIReady
    case onSceneActive(AppPage)
}
