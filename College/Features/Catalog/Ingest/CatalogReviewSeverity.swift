// CatalogReviewSeverity.swift
// Feature: Catalog
// Purpose: Catalog module — review queue severity (critical blocks ingest).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogReviewSeverity: String, Codable, Sendable, CaseIterable {
    case critical
    case warning
    case informational

    var blocksIngest: Bool {
        self == .critical
    }
}

extension CatalogReviewQueue {
    static var criticalItemCount: Int {
        load().filter { $0.severity == .critical }.count
    }

    static func enqueue(
        schoolID: String,
        reason: String,
        confidence: Double? = nil,
        severity: CatalogReviewSeverity = .warning,
        createdAt: Date = Date(),
        metrics: CatalogExtractorMetrics? = nil,
        contextMessages: [String] = []
    ) {
        var snapshotID: UUID?
        if metrics != nil || !contextMessages.isEmpty {
            let snapshot = CatalogReviewSnapshot.from(
                schoolID: schoolID,
                reason: reason,
                severity: severity,
                metrics: metrics,
                messages: contextMessages
            )
            CatalogReviewSnapshotStore.save(snapshot)
            snapshotID = snapshot.id
            CatalogEntityLLMValidator.scheduleAutoValidation(
                schoolID: schoolID,
                reason: reason,
                severity: severity,
                confidence: confidence,
                snapshot: snapshot
            )
        }
        enqueue(
            Item(
                schoolID: schoolID,
                reason: reason,
                confidence: confidence,
                createdAt: createdAt,
                severity: severity,
                snapshotID: snapshotID
            )
        )
    }
}
