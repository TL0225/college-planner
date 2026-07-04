// CatalogIRRoleDecision.swift
// Feature: Catalog
// Purpose: Architecture decision — Document IR is provenance + downstream consumer (P11).

import Foundation

/// P11 decision (Tier 3): layered `CatalogDocumentIR` remains **provenance-first**, not the
/// sole source of truth for persistence. Production ingest still writes normalized entities
/// (programs/courses/requirements) while IR is saved for replay, diff, and vector indexing.
///
/// Consumers (when `CatalogPlatformFlags.documentIREnabled`):
/// - `CatalogDocumentIRStore` — JSON cache per school + catalog version
/// - `UniversalCatalogScraperIRConsumer` — Modern Campus graph crawl
/// - `CatalogVectorIndexer` — chunk embeddings for `semanticCatalogSearch`
/// - Future: requirement AST reconciliation against IR nodes
///
/// Promoting IR to authoritative source requires Layout IR + Table IR maturity (P7/P19) and
/// evaluation gates (P22) on held-out schools — not enabled by default.
enum CatalogIRRoleDecision {
    static let mode: String = "provenance_with_consumers"

    static func shouldLoadIRForReplay(schoolID: String) -> Bool {
        CatalogPlatformFlags.documentIREnabled &&
        !schoolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
