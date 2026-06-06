// ToolbarTelemetry.swift
// Feature: App / Toolbar
// Purpose: Pluggable telemetry sink for toolbar dispatch layer.

import Foundation
import os

@MainActor
protocol ToolbarTelemetrySink {
    func track(action: ToolbarAction, owner: ToolbarHandlerOwner?)
}

struct NoOpToolbarTelemetry: ToolbarTelemetrySink, Sendable {
    func track(action: ToolbarAction, owner: ToolbarHandlerOwner?) {}
}

struct DebugToolbarTelemetry: ToolbarTelemetrySink, Sendable {
    private static let log = Logger(subsystem: "com.college.app", category: "Toolbar")

    func track(action: ToolbarAction, owner: ToolbarHandlerOwner?) {
        #if DEBUG
        Self.log.debug("dispatch action=\(String(describing: action), privacy: .public) owner=\(String(describing: owner), privacy: .public)")
        #endif
    }
}

@MainActor
final class MockToolbarTelemetry: ToolbarTelemetrySink {
    private(set) var events: [(ToolbarAction, ToolbarHandlerOwner?)] = []

    func track(action: ToolbarAction, owner: ToolbarHandlerOwner?) {
        events.append((action, owner))
    }

    func reset() {
        events.removeAll()
    }
}
