// LaunchPerformanceAcceptance.swift
// Feature: Debug
// Purpose: Debug module — LaunchPerformanceAcceptance.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Central place for launch / stall performance budgets used in telemetry and tests.
enum LaunchPerformanceAcceptance {
    /// Warn when preload pipeline wall time exceeds this (release). Part 11 / E-23.
    static let pipelineWallClockWarnMsRelease = 8_000
    /// More permissive budget for Debug (debugger / ASan / local disks).
    static let pipelineWallClockWarnMsDebug = 120_000

    static var pipelineWallClockWarnThresholdMs: Int {
        #if DEBUG
        pipelineWallClockWarnMsDebug
        #else
        pipelineWallClockWarnMsRelease
        #endif
    }

    /// `true` when duration is **beyond** the warning budget (should log + investigate).
    static func pipelineDurationExceedsBudget(durationMs: Int) -> Bool {
        durationMs > pipelineWallClockWarnThresholdMs
    }

    // MARK: - Academics audit

    /// Warn when `AcademicsView.loadAudit` wall time exceeds this (release). Part 11 / E-24.
    static let academicsAuditWarnMsRelease = 2_000
    /// More permissive budget for Debug (debugger / seeded fixtures).
    static let academicsAuditWarnMsDebug = 10_000

    static var academicsAuditWarnThresholdMs: Int {
        #if DEBUG
        academicsAuditWarnMsDebug
        #else
        academicsAuditWarnMsRelease
        #endif
    }

    static func academicsAuditDurationExceedsBudget(durationMs: Int) -> Bool {
        durationMs > academicsAuditWarnThresholdMs
    }

    // MARK: - Resident memory (RSS)

    enum ResidentMemoryScenario: CaseIterable {
        case coldLaunch
        case postAssistantIdle
        case academicsAudit
        case vectorReindex
        case backgroundForeground
    }

    static let coldLaunchResidentMemoryWarnMBRelease = 1_200
    static let coldLaunchResidentMemoryWarnMBDebug = 1_800

    static let postAssistantIdleResidentMemoryWarnMBRelease = 1_500
    static let postAssistantIdleResidentMemoryWarnMBDebug = 2_500

    static let academicsAuditResidentMemoryWarnMBRelease = 1_600
    static let academicsAuditResidentMemoryWarnMBDebug = 2_600

    static let vectorReindexResidentMemoryWarnMBRelease = 2_048
    static let vectorReindexResidentMemoryWarnMBDebug = 4_096

    static let backgroundForegroundResidentMemoryWarnMBRelease = 1_400
    static let backgroundForegroundResidentMemoryWarnMBDebug = 2_200

    static func residentMemoryWarnThresholdMB(for scenario: ResidentMemoryScenario) -> Int {
        switch scenario {
        case .coldLaunch:
            #if DEBUG
            return coldLaunchResidentMemoryWarnMBDebug
            #else
            return coldLaunchResidentMemoryWarnMBRelease
            #endif
        case .postAssistantIdle:
            #if DEBUG
            return postAssistantIdleResidentMemoryWarnMBDebug
            #else
            return postAssistantIdleResidentMemoryWarnMBRelease
            #endif
        case .academicsAudit:
            #if DEBUG
            return academicsAuditResidentMemoryWarnMBDebug
            #else
            return academicsAuditResidentMemoryWarnMBRelease
            #endif
        case .vectorReindex:
            #if DEBUG
            return vectorReindexResidentMemoryWarnMBDebug
            #else
            return vectorReindexResidentMemoryWarnMBRelease
            #endif
        case .backgroundForeground:
            #if DEBUG
            return backgroundForegroundResidentMemoryWarnMBDebug
            #else
            return backgroundForegroundResidentMemoryWarnMBRelease
            #endif
        }
    }

    /// `true` when resident memory is **beyond** the warning budget for the scenario.
    static func residentMemoryExceedsBudget(residentMB: Int, scenario: ResidentMemoryScenario) -> Bool {
        residentMB > residentMemoryWarnThresholdMB(for: scenario)
    }

    // MARK: - Shell navigation

    static let shellPageSwitchWarnMsRelease = 450
    static let shellPageSwitchWarnMsDebug = 1_200

    static let shellSidebarToggleWarnMsRelease = 100
    static let shellSidebarToggleWarnMsDebug = 900

    static let shellInspectorToggleWarnMsRelease = 350
    static let shellInspectorToggleWarnMsDebug = 1_000

    static let shellSearchFocusWarnMsRelease = 250
    static let shellSearchFocusWarnMsDebug = 800

    static var shellPageSwitchWarnThresholdMs: Int {
        #if DEBUG
        shellPageSwitchWarnMsDebug
        #else
        shellPageSwitchWarnMsRelease
        #endif
    }

    static var shellSidebarToggleWarnThresholdMs: Int {
        #if DEBUG
        shellSidebarToggleWarnMsDebug
        #else
        shellSidebarToggleWarnMsRelease
        #endif
    }

    static var shellInspectorToggleWarnThresholdMs: Int {
        #if DEBUG
        shellInspectorToggleWarnMsDebug
        #else
        shellInspectorToggleWarnMsRelease
        #endif
    }

    static var shellSearchFocusWarnThresholdMs: Int {
        #if DEBUG
        shellSearchFocusWarnMsDebug
        #else
        shellSearchFocusWarnMsRelease
        #endif
    }

    static func shellPageSwitchExceedsBudget(durationMs: Int) -> Bool {
        durationMs > shellPageSwitchWarnThresholdMs
    }

    static func shellSidebarToggleExceedsBudget(durationMs: Int) -> Bool {
        durationMs > shellSidebarToggleWarnThresholdMs
    }

    static func shellInspectorToggleExceedsBudget(durationMs: Int) -> Bool {
        durationMs > shellInspectorToggleWarnThresholdMs
    }

    static func shellSearchFocusExceedsBudget(durationMs: Int) -> Bool {
        durationMs > shellSearchFocusWarnThresholdMs
    }
}
