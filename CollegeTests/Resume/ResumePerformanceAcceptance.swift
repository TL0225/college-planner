// ResumePerformanceAcceptance.swift
// Feature: Resume Tests
// Purpose: XCTest performance budget constants for resume builder gates.

import Foundation

enum ResumePerformanceAcceptance {
    static let typstCompileBudgetMsRelease = 800
    static let typstCompileBudgetMsDebug = 3_000

    static let fastPathIngestBudgetMsRelease = 500
    static let fastPathIngestBudgetMsDebug = 2_000

    static var typstCompileBudgetMs: Int {
        #if DEBUG
        typstCompileBudgetMsDebug
        #else
        typstCompileBudgetMsRelease
        #endif
    }

    static var fastPathIngestBudgetMs: Int {
        #if DEBUG
        fastPathIngestBudgetMsDebug
        #else
        fastPathIngestBudgetMsRelease
        #endif
    }

    static func typstCompileExceedsBudget(durationMs: Int) -> Bool {
        durationMs > typstCompileBudgetMs
    }

    static func fastPathIngestExceedsBudget(durationMs: Int) -> Bool {
        durationMs > fastPathIngestBudgetMs
    }
}
