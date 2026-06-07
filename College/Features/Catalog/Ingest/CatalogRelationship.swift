// CatalogRelationship.swift
// Feature: Catalog
// Purpose: Catalog module — graph edges between stable catalog entities.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogRelationshipKind: String, Codable, Sendable, CaseIterable {
    case prerequisite
    case corequisite
    case exclusion
    case equivalent
    case programRequiresCourse
    case programElectivePool
    case concentration
}

struct CatalogRelationship: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let fromStableID: UUID
    let toStableID: UUID
    let kind: CatalogRelationshipKind
    let catalogVersionID: String
    let provenance: CatalogProvenance?

    var stableID: UUID { id }

    init(
        id: UUID = UUID(),
        fromStableID: UUID,
        toStableID: UUID,
        kind: CatalogRelationshipKind,
        catalogVersionID: String,
        provenance: CatalogProvenance? = nil
    ) {
        self.id = id
        self.fromStableID = fromStableID
        self.toStableID = toStableID
        self.kind = kind
        self.catalogVersionID = catalogVersionID
        self.provenance = provenance
    }
}
