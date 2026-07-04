// AcademicCalendarDiscoveryTelemetry.swift
// Feature: Calendar
// Purpose: Telemetry for academic calendar auto-discovery resolution.

import Foundation

struct AcademicCalendarDiscoveryTelemetryPayload: Sendable, Equatable {
  var resolvedTier: String
  var resolverConfidenceMargin: Int
  var isOverrideNeeded: Bool
  var discoverySource: String
  var hopCount: Int
  var elapsedMs: Int
  var schoolID: String
  var departmentKey: String
  var outcome: String
}

enum AcademicCalendarDiscoveryTelemetry {
  static func emit(_ payload: AcademicCalendarDiscoveryTelemetryPayload) {
    let message = [
      "outcome=\(payload.outcome)",
      "resolved_tier=\(payload.resolvedTier)",
      "resolver_confidence_margin=\(payload.resolverConfidenceMargin)",
      "is_override_needed=\(payload.isOverrideNeeded)",
      "discovery_source=\(payload.discoverySource)",
      "hop_count=\(payload.hopCount)",
      "elapsed_ms=\(payload.elapsedMs)",
      "school_id=\(payload.schoolID)",
      "department_key=\(payload.departmentKey)",
    ].joined(separator: " ")

    DiagnosticsEvent.emit(
      subsystem: .sync,
      severity: .info,
      code: "calendar_auto_discovery_resolution",
      message: message,
      category: "academic.calendar"
    )

    ProductAnalytics.track(
      .calendarAutoDiscoveryResolution,
      properties: [
        "outcome": payload.outcome,
        "resolved_tier": payload.resolvedTier,
        "resolver_confidence_margin": "\(payload.resolverConfidenceMargin)",
        "is_override_needed": payload.isOverrideNeeded ? "true" : "false",
        "discovery_source": payload.discoverySource,
        "hop_count": "\(payload.hopCount)",
        "elapsed_ms": "\(payload.elapsedMs)",
        "school_id": payload.schoolID,
        "department_key": payload.departmentKey,
      ]
    )
  }
}
