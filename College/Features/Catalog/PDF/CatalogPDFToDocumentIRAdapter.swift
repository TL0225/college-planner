// CatalogPDFToDocumentIRAdapter.swift
// Feature: Catalog
// Purpose: Map classified PDF blocks → shared CatalogDocumentIR (Tier 2).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPDFToDocumentIRAdapter {
    static func buildIR(
        schoolID: String,
        catalogVersionID: String,
        sourceURL: String,
        classifiedBlocks: [CatalogPDFClassifiedBlock],
        layoutProfileID: String = "pdf-blocks",
        layoutConfidence: Double = 0.75,
        ingestRunID: UUID = UUID()
    ) -> CatalogDocumentIR {
        var nodes: [CatalogDocumentNode] = []
        var sectionIDByPath: [String: UUID] = [:]

        for block in classifiedBlocks {
            let pathKey = block.headingPath.joined(separator: "›")
            let sectionID = ensureSection(
                path: block.headingPath,
                pathKey: pathKey,
                sourceURL: sourceURL,
                sectionKind: block.sectionKind,
                nodes: &nodes,
                sectionIDByPath: &sectionIDByPath
            )
            let depth = block.headingPath.count + 1
            nodes.append(
                CatalogDocumentNode(
                    parentID: sectionID,
                    depth: depth,
                    kind: nodeKind(for: block.type),
                    text: trimmedBlockText(block),
                    sourceURL: sourceURL,
                    elementSignature: "pdf.\(block.type.rawValue).p\(block.block.primaryPage)",
                    sectionLabel: sectionLabel(for: block.sectionKind)
                )
            )
        }

        let confidence = CatalogExtractionConfidence(
            score: layoutConfidence,
            reasons: ["pdf_adapter", "blocks:\(classifiedBlocks.count)", "nodes:\(nodes.count)"]
        )
        return CatalogDocumentIR.build(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: "pdf",
            layoutProfileID: layoutProfileID,
            nodes: nodes,
            layoutConfidence: confidence,
            ingestRunID: ingestRunID
        )
    }

    private static func ensureSection(
        path: [String],
        pathKey: String,
        sourceURL: String,
        sectionKind: CatalogPDFSectionKind?,
        nodes: inout [CatalogDocumentNode],
        sectionIDByPath: inout [String: UUID]
    ) -> UUID {
        if let existing = sectionIDByPath[pathKey] {
            return existing
        }
        let parentPathKey = path.dropLast().joined(separator: "›")
        let parentID = parentPathKey.isEmpty ? nil : sectionIDByPath[parentPathKey]
        let depth = max(0, path.count)
        let sectionID = UUID()
        nodes.append(
            CatalogDocumentNode(
                id: sectionID,
                parentID: parentID,
                depth: depth,
                kind: .section,
                text: path.last,
                sourceURL: sourceURL,
                elementSignature: "pdf.section.\(sectionKind?.rawValue ?? "general")",
                sectionLabel: sectionLabel(for: sectionKind)
            )
        )
        sectionIDByPath[pathKey] = sectionID
        return sectionID
    }

    private static func nodeKind(for type: CatalogBlockType) -> CatalogNodeKind {
        switch type {
        case .course: return .courseBlock
        case .program: return .programBlock
        case .requirement: return .requirementTable
        case .heading: return .heading
        case .policy: return .paragraph
        case .table, .faculty, .unknown: return .unknown
        }
    }

    private static func sectionLabel(for kind: CatalogPDFSectionKind?) -> CatalogSectionLabel {
        switch kind {
        case .courseDescriptions: return .courses
        case .programs: return .programs
        case .degreeRequirements: return .requirements
        case .policies: return .policies
        case .ignored, .none: return .general
        }
    }

    private static func trimmedBlockText(_ block: CatalogPDFClassifiedBlock) -> String? {
        let text = block.block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(4096))
    }
}
