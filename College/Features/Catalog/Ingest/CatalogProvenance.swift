// CatalogProvenance.swift
// Feature: Catalog
// Purpose: Catalog module — traceability for extracted catalog entities.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogProvenance: Codable, Sendable, Equatable {
    let sourceURL: String
    let layoutProfileID: String
    let documentNodeID: UUID
    let sectionPath: [UUID]
    let parserVersion: String
    let parserCapabilityVersion: String
    let catalogVersionID: String
    let extractedAt: Date
    let ingestRunID: UUID

    init(
        sourceURL: String,
        layoutProfileID: String,
        documentNodeID: UUID,
        sectionPath: [UUID] = [],
        parserVersion: String = CatalogParserCapability.version,
        parserCapabilityVersion: String = CatalogParserCapability.version,
        catalogVersionID: String,
        extractedAt: Date = Date(),
        ingestRunID: UUID
    ) {
        self.sourceURL = sourceURL
        self.layoutProfileID = layoutProfileID
        self.documentNodeID = documentNodeID
        self.sectionPath = sectionPath
        self.parserVersion = parserVersion
        self.parserCapabilityVersion = parserCapabilityVersion
        self.catalogVersionID = catalogVersionID
        self.extractedAt = extractedAt
        self.ingestRunID = ingestRunID
    }
}

extension CatalogProvenance {
    init(
        canonical provenance: CatalogCanonicalIR.Provenance,
        layoutProfileID: String,
        documentNodeID: UUID,
        sectionPath: [UUID],
        catalogVersionID: String,
        extractedAt: Date,
        ingestRunID: UUID
    ) {
        self.init(
            sourceURL: provenance.documentURL,
            layoutProfileID: layoutProfileID,
            documentNodeID: documentNodeID,
            sectionPath: sectionPath,
            parserVersion: provenance.parserVersion,
            parserCapabilityVersion: provenance.parserCapabilityVersion,
            catalogVersionID: catalogVersionID,
            extractedAt: extractedAt,
            ingestRunID: ingestRunID
        )
    }

    func canonicalProvenance(confidence: Double? = nil) -> CatalogCanonicalIR.Provenance {
        CatalogCanonicalIR.Provenance(
            documentURL: sourceURL,
            parserVersion: parserVersion,
            parserCapabilityVersion: parserCapabilityVersion,
            pageStart: nil,
            pageEnd: nil,
            confidence: confidence
        )
    }
}
