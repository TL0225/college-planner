// CatalogDocumentIR.swift
// Feature: Catalog
// Purpose: Catalog module — immutable semantic document tree for catalog ingest.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogNodeKind: String, Codable, Sendable, CaseIterable {
    case section
    case heading
    case paragraph
    case courseBlock
    case programBlock
    case requirementTable
    case linkList
    case unknown
}

enum CatalogSectionLabel: String, Codable, Sendable, CaseIterable {
    case programs
    case courses
    case requirements
    case policies
    case general
    case unknown
}

struct CatalogDocumentNode: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let parentID: UUID?
    let depth: Int
    let kind: CatalogNodeKind
    let text: String?
    let sourceURL: String?
    let elementSignature: String?
    let sectionLabel: CatalogSectionLabel?

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        depth: Int,
        kind: CatalogNodeKind,
        text: String? = nil,
        sourceURL: String? = nil,
        elementSignature: String? = nil,
        sectionLabel: CatalogSectionLabel? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.depth = depth
        self.kind = kind
        self.text = text
        self.sourceURL = sourceURL
        self.elementSignature = elementSignature
        self.sectionLabel = sectionLabel
    }
}

struct CatalogDocumentIR: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let engine: String
    let layoutProfileID: String
    let nodes: [CatalogDocumentNode]
    let layoutConfidence: CatalogExtractionConfidence
    let ingestRunID: UUID
    let builtAt: Date

    static func build(
        schoolID: String,
        catalogVersionID: String,
        engine: String,
        layoutProfileID: String,
        nodes: [CatalogDocumentNode],
        layoutConfidence: CatalogExtractionConfidence,
        ingestRunID: UUID = UUID(),
        builtAt: Date = Date()
    ) -> CatalogDocumentIR {
        CatalogDocumentIR(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: engine,
            layoutProfileID: layoutProfileID,
            nodes: nodes,
            layoutConfidence: layoutConfidence,
            ingestRunID: ingestRunID,
            builtAt: builtAt
        )
    }

    func sectionPath(to nodeID: UUID) -> [UUID] {
        guard !nodes.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var path: [UUID] = []
        var current = byID[nodeID]
        while let node = current {
            path.insert(node.id, at: 0)
            guard let parentID = node.parentID else { break }
            current = byID[parentID]
        }
        return path
    }
}
