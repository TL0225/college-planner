// ProductAnalytics.swift
// Feature: Core / Services
// Purpose: Opt-in product funnel events (M30-081).

import Foundation

enum ProductAnalyticsEvent: String, Sendable {
  case onboardingCompleted
  case ftueStepCompleted
  case pageVisited
  case assistantMessageSent
  case courseAdded
  case resumeExported
  case resumeBuilderOpened
  case resumeDraftSaved
  case resumePlatformVariantCreated
  case resumeApplyLaunched
  case backupExported
  case backupImported
  case calendarAutoDiscoveryResolution
}

enum ProductAnalytics {
    static let optInKey = "analytics.product.optIn"

    static var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: optInKey)
    }

    static func setOptedIn(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: optInKey)
    }

    /// Records a coarse funnel event when the user has opted in. Never includes message bodies or grades.
    static func track(_ event: ProductAnalyticsEvent, properties: [String: String] = [:]) {
        guard isOptedIn else { return }
        let detail = properties.isEmpty
            ? event.rawValue
            : "\(event.rawValue) {\(properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))}"
        DiagnosticsEvent.emit(
            subsystem: .app,
            severity: .info,
            code: "analytics.\(event.rawValue)",
            message: detail,
            category: "product.analytics"
        )
    }
}
