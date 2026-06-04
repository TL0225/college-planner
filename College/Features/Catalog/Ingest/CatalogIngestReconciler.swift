// CatalogIngestReconciler.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIngestReconciler.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogIngestReconciler {
    /// v1 reconciliation shim:
    /// - Central place to emit reconcile diagnostics for all ingest sources.
    /// - Destructive reconcile rules still happen in existing import/save routines.
    @MainActor
    static func reconcile(after snapshot: CatalogIngestSnapshot) -> CatalogReconcileSummary {
        let upserted = snapshot.courseCount + snapshot.programCount + snapshot.requirementCount + snapshot.policyCount
        let summary = CatalogReconcileSummary(
            upserted: upserted,
            archived: 0,
            deleted: 0
        )
        DebugLogger.shared.log(
            "[CatalogReconciler] school=\(snapshot.schoolID) scope=\(String(describing: snapshot.scope)) format=\(snapshot.format) upserted=\(summary.upserted) archived=\(summary.archived) deleted=\(summary.deleted)",
            category: .system,
            level: .info
        )
        return summary
    }
}
