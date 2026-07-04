// ShellPerformanceTiming.swift
// Feature: Debug / Diagnostics
// Purpose: Shell navigation timing spans (sidebar, page, inspector, search).

import Foundation

@MainActor
enum ShellPerformanceTiming {
    enum Operation: String, Sendable {
        case pageSwitch
        case sidebarToggle
        case inspectorToggle
        case searchFocus
    }

    private static var starts: [Operation: CFAbsoluteTime] = [:]

    static func begin(_ operation: Operation) {
        starts[operation] = CFAbsoluteTimeGetCurrent()
    }

    @discardableResult
    static func end(_ operation: Operation, detail: String) -> Int {
        guard let start = starts.removeValue(forKey: operation) else { return 0 }
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        record(operation: operation, detail: detail, durationMs: durationMs)
        return durationMs
    }

    private static func record(operation: Operation, detail: String, durationMs: Int) {
        let budgetMs: Int?
        let exceedsBudget: Bool
        switch operation {
        case .pageSwitch:
            budgetMs = LaunchPerformanceAcceptance.shellPageSwitchWarnThresholdMs
            exceedsBudget = LaunchPerformanceAcceptance.shellPageSwitchExceedsBudget(durationMs: durationMs)
        case .sidebarToggle:
            budgetMs = LaunchPerformanceAcceptance.shellSidebarToggleWarnThresholdMs
            exceedsBudget = LaunchPerformanceAcceptance.shellSidebarToggleExceedsBudget(durationMs: durationMs)
        case .inspectorToggle:
            budgetMs = LaunchPerformanceAcceptance.shellInspectorToggleWarnThresholdMs
            exceedsBudget = LaunchPerformanceAcceptance.shellInspectorToggleExceedsBudget(durationMs: durationMs)
        case .searchFocus:
            budgetMs = LaunchPerformanceAcceptance.shellSearchFocusWarnThresholdMs
            exceedsBudget = LaunchPerformanceAcceptance.shellSearchFocusExceedsBudget(durationMs: durationMs)
        }

        Task {
            await LoadOperationTrace.recordCompleted(
                name: "shell.\(operation.rawValue)",
                category: .shell,
                durationMs: durationMs,
                budgetMs: budgetMs,
                executionContext: .mainThread,
                metadata: ["detail": detail]
            )
        }

        guard exceedsBudget else { return }
        DiagnosticsEvent.emit(
            subsystem: .runtime,
            severity: .warning,
            code: "shell.\(operation.rawValue).slow",
            message: "\(operation.rawValue) took \(durationMs)ms (\(detail))",
            category: "shell.performance"
        )
    }
}
