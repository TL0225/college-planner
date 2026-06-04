// AuditCatalogLookupBridge.swift
// Feature: Academics
// Purpose: Academics module — AuditCatalogCourseSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Sendable catalog row for Academics audit (Phase 3 P0 — off-main batch lookup).
struct AuditCatalogCourseSnapshot: Sendable, Equatable {
    let creditsDisplayText: String
    let title: String
}

enum AuditCatalogLookupBridge {
    /// Resolves many course codes on a background `ModelContext` (one catalog scan + in-memory match).
    static func batchMatchingOffMain(
        universityID: UUID,
        codes: [String]
    ) async -> [String: AuditCatalogCourseSnapshot] {
        let container = await MainActor.run { AppDataStore.shared.activeCatalogContainer }
        guard let container else { return [:] }

        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard let matched = try? AuditCatalogBatchLookupQuery.matchingBatch(
                universityID: universityID,
                codes: codes,
                context: context
            ) else {
                return [:]
            }
            var out: [String: AuditCatalogCourseSnapshot] = [:]
            out.reserveCapacity(matched.count)
            for (upper, course) in matched {
                let credits = {
                    let base = Int(course.credits)
                    return base > 0 ? String(base) : ""
                }()
                let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
                out[upper] = AuditCatalogCourseSnapshot(creditsDisplayText: credits, title: title)
            }
            return out
        }.value
    }
}
