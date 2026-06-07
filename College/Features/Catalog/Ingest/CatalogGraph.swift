// CatalogGraph.swift
// Feature: Catalog
// Purpose: Catalog module — immutable discovery graph of bulletin page URLs.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPageKind: String, Codable, Sendable, CaseIterable {
    case index
    case programListing
    case programDetail
    case courseListing
    case courseDetail
    case policy
    case unknown
}

struct CatalogPageNode: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let url: String
    let kind: CatalogPageKind
    let parentNodeID: UUID?
    let depth: Int
    let catalogVersionID: String
    let discoveryConfidence: Double?

    init(
        id: UUID = UUID(),
        url: String,
        kind: CatalogPageKind,
        parentNodeID: UUID? = nil,
        depth: Int = 0,
        catalogVersionID: String,
        discoveryConfidence: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.parentNodeID = parentNodeID
        self.depth = depth
        self.catalogVersionID = catalogVersionID
        self.discoveryConfidence = discoveryConfidence
    }
}

struct CatalogGraph: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let engine: String
    let nodes: [CatalogPageNode]
    let discoveredAt: Date
    let sourceSignature: String

    var nodeCount: Int { nodes.count }

    func urls(ofKind kind: CatalogPageKind) -> [String] {
        nodes
            .filter { $0.kind == kind }
            .map(\.url)
            .sorted()
    }

    var extractablePageURLs: [String] {
        let extractableKinds: Set<CatalogPageKind> = [
            .programDetail,
            .courseListing,
            .courseDetail,
            .programListing
        ]
        return nodes
            .filter { extractableKinds.contains($0.kind) }
            .map(\.url)
            .sorted()
    }
}
