// DiagnosticsHealthReport.swift
// Feature: Debug
// Purpose: Plain-language health band (Good / Warning / Critical) for the Diagnostics Center.

import Foundation

enum DiagnosticsHealthBand: String, Codable, Sendable {
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"
}

struct DiagnosticsHealthCheck: Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: DiagnosticsHealthBand
    let detail: String
}

/// Where a warning bullet should take the user (or what inline action it offers).
enum DiagnosticsHealthAction: String, Sendable, Equatable {
    case viewCrashes
    case viewSessions
    case viewCatalog
    case loadAssistantModel
    case viewPerformance
    case none
}

struct DiagnosticsHealthWarning: Sendable, Equatable, Identifiable {
    let id: String
    let message: String
    let action: DiagnosticsHealthAction
}

struct DiagnosticsHealthReport: Sendable, Equatable {
    let band: DiagnosticsHealthBand
    let headline: String
    let checks: [DiagnosticsHealthCheck]
    let warnings: [DiagnosticsHealthWarning]
    let generatedAt: Date
}

enum DiagnosticsHealthReportBuilder {
    static func generate(now: Date = Date()) async -> DiagnosticsHealthReport {
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86_400)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)

        let crashCount = await DiagnosticsEventStore.shared.countEvents(
            since: thirtyDaysAgo,
            severity: .critical
        ) + CrashReportStore.allReportURLs(since: thirtyDaysAgo).count

        let memoryWarnings = await DiagnosticsEventStore.shared.countEvents(
            since: sevenDaysAgo,
            severity: .warning
        )

        let catalogFailures = await DiagnosticsEventStore.shared.fetchRecent(
            limit: 20,
            since: sevenDaysAgo,
            subsystem: .catalog
        ).filter { $0.severity == .error || $0.severity == .critical }.count

        let modelFailures = await DiagnosticsEventStore.shared.fetchRecent(
            limit: 20,
            since: sevenDaysAgo,
            subsystem: .model
        ).filter { $0.severity == .error || $0.severity == .critical }.count

        let modelLoaded = UserDefaults.standard.bool(forKey: AssistantPlannerIndexingSettings.indexReadyKey)

        let lastExitClean: Bool = {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "College.session.lastExitWasClean") != nil else { return true }
            return defaults.bool(forKey: "College.session.lastExitWasClean")
        }()

        var checks: [DiagnosticsHealthCheck] = []
        var warnings: [DiagnosticsHealthWarning] = []

        let crashBand: DiagnosticsHealthBand = crashCount > 0 ? (crashCount >= 2 ? .critical : .warning) : .good
        checks.append(.init(
            id: "crashes",
            title: "Crashes",
            status: crashBand,
            detail: crashCount == 0 ? "No crashes in the last 30 days." : "\(crashCount) crash-related event(s) in the last 30 days."
        ))

        // Deduplicate the crash and "unexpected session end" signals: an unclean exit
        // is most often the *same* event as a recorded crash, so we don't double-count it.
        if crashCount > 0 {
            let message: String
            if lastExitClean {
                message = crashCount == 1 ? "1 crash in the last 30 days." : "\(crashCount) crashes in the last 30 days."
            } else {
                message = crashCount == 1
                    ? "A crash ended your previous session unexpectedly."
                    : "\(crashCount) crashes recently — the last ended your session unexpectedly."
            }
            warnings.append(.init(id: "crashes", message: message, action: .viewCrashes))
        } else if !lastExitClean {
            warnings.append(.init(
                id: "session",
                message: "Previous session ended unexpectedly.",
                action: .viewSessions
            ))
        }

        let catalogBand: DiagnosticsHealthBand = catalogFailures > 0 ? .warning : .good
        checks.append(.init(
            id: "catalog",
            title: "Course catalog",
            status: catalogBand,
            detail: catalogFailures == 0 ? "Catalog looks healthy." : "Catalog update issues detected recently."
        ))
        if catalogFailures > 0 {
            warnings.append(.init(
                id: "catalog",
                message: "Course catalog update had problems.",
                action: .viewCatalog
            ))
        }

        let modelBand: DiagnosticsHealthBand = modelFailures > 0 ? .warning : (modelLoaded ? .good : .warning)
        checks.append(.init(
            id: "model",
            title: "Assistant model",
            status: modelBand,
            detail: modelLoaded ? "On-device model is ready." : "Assistant model isn't fully loaded."
        ))
        if !modelLoaded {
            warnings.append(.init(
                id: "model",
                message: "Assistant model isn't loaded.",
                action: .loadAssistantModel
            ))
        }

        let memoryBand: DiagnosticsHealthBand = memoryWarnings > 2 ? .warning : .good
        checks.append(.init(
            id: "memory",
            title: "Memory",
            status: memoryBand,
            detail: memoryWarnings == 0 ? "No recent memory pressure." : "Memory pressure events recently."
        ))
        if memoryWarnings > 0 {
            warnings.append(.init(
                id: "memory",
                message: "Memory pressure events recently.",
                action: .viewPerformance
            ))
        }

        let sessionBand: DiagnosticsHealthBand = lastExitClean ? .good : .warning
        checks.append(.init(
            id: "session",
            title: "Last session",
            status: sessionBand,
            detail: lastExitClean ? "Previous session ended normally." : "Previous session may have ended unexpectedly."
        ))

        let overall: DiagnosticsHealthBand
        if checks.contains(where: { $0.status == .critical }) {
            overall = .critical
        } else if checks.contains(where: { $0.status == .warning }) {
            overall = .warning
        } else {
            overall = .good
        }

        let headline: String
        switch overall {
        case .good:
            headline = "Everything looks healthy."
        case .warning:
            headline = warnings.count == 1
                ? "1 thing needs attention."
                : "\(warnings.count) things need attention."
        case .critical:
            headline = "Critical issues detected — review crashes first."
        }

        return DiagnosticsHealthReport(
            band: overall,
            headline: headline,
            checks: checks,
            warnings: Array(warnings.prefix(5)),
            generatedAt: now
        )
    }
}
