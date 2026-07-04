// CatalogEntityLineage.swift
// Feature: Catalog
// Purpose: Full provenance lineage per extracted entity (P10).

import Foundation

struct CatalogEntityLineage: Codable, Sendable, Equatable {
    let entityKind: String
    let entityKey: String
    let sourceURL: String?
    let pageStart: Int?
    let pageEnd: Int?
    let layoutBlockID: UUID?
    let tableIRID: UUID?
    let parserVersion: String
    let extractionRule: String?
    let confidence: Double?
    let validationStatus: String?
    let catalogVersionID: String?
    let ingestRunID: UUID?
    let parentLineageKey: String?

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> CatalogEntityLineage? {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CatalogEntityLineage.self, from: data) else {
            return nil
        }
        return decoded
    }
}

enum CatalogEntityLineageBuilder {
    static func forProgram(
        name: String,
        sourceURL: String?,
        page: Int?,
        layoutBlockID: UUID? = nil,
        confidence: Double?,
        catalogVersionID: String,
        ingestRunID: UUID,
        rule: String = "program_extractor"
    ) -> CatalogEntityLineage {
        CatalogEntityLineage(
            entityKind: "program",
            entityKey: name,
            sourceURL: sourceURL,
            pageStart: page,
            pageEnd: page,
            layoutBlockID: layoutBlockID,
            tableIRID: nil,
            parserVersion: CatalogParserCapability.version,
            extractionRule: rule,
            confidence: confidence,
            validationStatus: nil,
            catalogVersionID: catalogVersionID,
            ingestRunID: ingestRunID,
            parentLineageKey: nil
        )
    }

    static func merge(into provenanceJSON: String?, lineage: CatalogEntityLineage) -> String? {
        lineage.jsonString() ?? provenanceJSON
    }
}
