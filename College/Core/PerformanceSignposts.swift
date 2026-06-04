// PerformanceSignposts.swift
// Feature: Core
// Purpose: Core module — PerformanceSignposts.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os

/// Centralized performance logging and Instruments signposts for hot paths tracked in Phase 0 baselines.
enum PerformanceSignposts {
    static let log = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)
    static let logger = Logger(subsystem: "Timothy.College", category: "Performance")

    // MARK: - Academics audit

    @discardableResult
    static func beginLoadAudit() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "LoadAudit", signpostID: id)
        return id
    }

    static func endLoadAudit(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "LoadAudit", signpostID: signpostID)
    }

    // MARK: - Credit progress summary

    @discardableResult
    static func beginCreditsProgressSummary() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "CreditsProgressSummary", signpostID: id)
        return id
    }

    static func endCreditsProgressSummary(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "CreditsProgressSummary", signpostID: signpostID)
    }

    // MARK: - LLM lifecycle

    @discardableResult
    static func beginLLMLoad() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "LLMLoad", signpostID: id)
        return id
    }

    static func endLLMLoad(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "LLMLoad", signpostID: signpostID)
    }

    @discardableResult
    static func beginLLMUnload(reason: String = "explicit") -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "LLMUnload",
            signpostID: id,
            "reason=%{public}s",
            reason
        )
        return id
    }

    static func endLLMUnload(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "LLMUnload", signpostID: signpostID)
    }

    // MARK: - Catalog vector index

    @discardableResult
    static func beginCatalogVectorReindex(universityID: UUID, reason: String) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "CatalogVectorReindex",
            signpostID: id,
            "university=%{public}s reason=%{public}s",
            universityID.uuidString,
            reason
        )
        return id
    }

    static func endCatalogVectorReindex(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "CatalogVectorReindex", signpostID: signpostID)
    }

    // MARK: - Budget warnings

    static func logBudgetExceeded(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }
}
