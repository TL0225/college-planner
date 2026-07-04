// DiagnosticsRegistry.swift
// Feature: Debug
// Purpose: Discoverable diagnostic sources for the unified Diagnostics Center.

import Foundation

/// Service filter IDs used across the Diagnostics Center UI.
enum DiagnosticsServiceID: String, CaseIterable, Identifiable, Sendable {
    case all
    case app
    case runtime
    case crashes
    case performance
    case assistant
    case catalog
    case calendarGoogle = "calendar_google"
    case connectivity
    case metrickit
    #if DEBUG
    case developer
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .app: return "App"
        case .runtime: return "Runtime"
        case .crashes: return "Crashes"
        case .performance: return "Performance"
        case .assistant: return "Assistant & Models"
        case .catalog: return "Catalog & Data"
        case .calendarGoogle: return "Calendar & Google"
        case .connectivity: return "Connectivity"
        case .metrickit: return "MetricKit"
        #if DEBUG
        case .developer: return "Developer"
        #endif
        }
    }

    static var visibleCases: [DiagnosticsServiceID] {
        #if DEBUG
        allCases
        #else
        [.all, .app, .runtime, .crashes, .performance, .assistant, .catalog, .calendarGoogle, .connectivity, .metrickit]
        #endif
    }
}

protocol DiagnosticsSource: Sendable {
    var id: DiagnosticsServiceID { get }
    var title: String { get }
    func summary() async -> String
    func artifactURLs() -> [URL]
    var userDefaultsKeys: [String] { get }
}

struct StaticDiagnosticsSource: DiagnosticsSource {
    let id: DiagnosticsServiceID
    let title: String
    let summaryText: String
    let artifacts: [DiagnosticsArtifact]

    func summary() async -> String { summaryText }

    func artifactURLs() -> [URL] {
        artifacts.compactMap(\.url)
    }

    var userDefaultsKeys: [String] {
        artifacts.flatMap(\.userDefaultsKeys)
    }
}

enum DiagnosticsRegistry {
    static let sources: [any DiagnosticsSource] = [
        StaticDiagnosticsSource(
            id: .app,
            title: "App",
            summaryText: "General app lifecycle and navigation logs.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "logs" }
        ),
        StaticDiagnosticsSource(
            id: .runtime,
            title: "Runtime",
            summaryText: "Heartbeat telemetry, service states, and main-thread stall detection.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "logs" || $0.id == "event_store" }
        ),
        StaticDiagnosticsSource(
            id: .crashes,
            title: "Crashes & Sessions",
            summaryText: "Crash reports, signal captures, and session termination markers.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "crashes" }
        ),
        StaticDiagnosticsSource(
            id: .performance,
            title: "Performance",
            summaryText: "Memory footprint, launch timing, and runtime performance snapshots.",
            artifacts: DiagnosticsArtifacts.all.filter { ["event_store", "launch_history", "logs"].contains($0.id) }
        ),
        StaticDiagnosticsSource(
            id: .assistant,
            title: "Assistant & Models",
            summaryText: "On-device model state, MLX memory, and planner index readiness.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "logs" || $0.id == "event_store" }
        ),
        StaticDiagnosticsSource(
            id: .catalog,
            title: "Catalog & Data",
            summaryText: "Catalog ingest, PDF scrape, integrity, and review queue diagnostics.",
            artifacts: DiagnosticsArtifacts.all.filter { ["catalog_data", "catalog_userdefaults", "migrated_reports"].contains($0.id) }
        ),
        StaticDiagnosticsSource(
            id: .calendarGoogle,
            title: "Calendar & Google",
            summaryText: "Google Calendar sync and calendar integration logs.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "google_debug" || $0.id == "logs" }
        ),
        StaticDiagnosticsSource(
            id: .connectivity,
            title: "Connectivity",
            summaryText: "Network and integration debug logs.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "google_debug" || $0.id == "logs" }
        ),
        StaticDiagnosticsSource(
            id: .metrickit,
            title: "MetricKit",
            summaryText: "OS-level crash, hang, CPU, disk, and daily performance metrics.",
            artifacts: DiagnosticsArtifacts.all.filter { $0.id == "metrickit" || $0.id == "event_store" }
        ),
    ]

    static func source(for id: DiagnosticsServiceID) -> (any DiagnosticsSource)? {
        guard id != .all else { return nil }
        return sources.first { $0.id == id }
    }

    static func artifactURLs(for service: DiagnosticsServiceID) -> [URL] {
        if service == .all {
            return DiagnosticsArtifacts.allArtifactURLs(existingOnly: true)
        }
        return source(for: service)?.artifactURLs().filter {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? []
    }
}
