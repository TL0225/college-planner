// CatalogPDFDocumentModel.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFDocumentSection.
// Data: CollegePersistence / repositories when applicable.

import CoreGraphics
import Foundation

// MARK: - Block taxonomy

enum CatalogBlockType: String, Sendable, Codable {
    case course
    case program
    case requirement
    case policy
    case heading
    case table
    case faculty
    case unknown
}

// MARK: - Section kinds (outline-driven page ranges)

enum CatalogPDFSectionKind: String, Sendable, Codable {
    case courseDescriptions
    case programs
    case degreeRequirements
    case policies
    case ignored
}

struct CatalogPDFDocumentSection: Sendable, Codable {
    let kind: CatalogPDFSectionKind
    let confidence: Float
    let startPage: Int
    let endPage: Int
}

struct CatalogPDFHealthReport: Sendable, Codable {
    let pageCount: Int
    let outlineEntryCount: Int
    let lowTextDensityPages: Int
    let estimatedOCRPages: Int
    let layoutNote: String?
}

// MARK: - Geometry-ready line (v1: indent heuristic; rect/font optional)

struct CatalogPDFLine: Sendable, Hashable {
    let text: String
    let pageIndex: Int
    let lineIndexOnPage: Int
    let indentLevel: Int
    let rect: CGRect?
    let fontSize: CGFloat?
    let isBold: Bool?

    init(
        text: String,
        pageIndex: Int,
        lineIndexOnPage: Int,
        indentLevel: Int = 0,
        rect: CGRect? = nil,
        fontSize: CGFloat? = nil,
        isBold: Bool? = nil
    ) {
        self.text = text
        self.pageIndex = pageIndex
        self.lineIndexOnPage = lineIndexOnPage
        self.indentLevel = indentLevel
        self.rect = rect
        self.fontSize = fontSize
        self.isBold = isBold
    }
}

// MARK: - Layout IR

struct CatalogPDFTextBlock: Sendable, Hashable {
    let lines: [CatalogPDFLine]
    var text: String { lines.map(\.text).joined(separator: "\n") }
    let pageRange: ClosedRange<Int>

    var primaryPage: Int { lines.first?.pageIndex ?? pageRange.lowerBound }
}

// MARK: - Classification

struct ClassificationEvidence: Sendable, Codable {
    let matchedRules: [String]
    let positiveSignals: [String]
    let negativeSignals: [String]
}

struct CatalogPDFClassifiedBlock: Sendable {
    let block: CatalogPDFTextBlock
    let type: CatalogBlockType
    let confidence: Float
    let headingPath: [String]
    let sectionKind: CatalogPDFSectionKind?
    let evidence: ClassificationEvidence
}

// MARK: - Ingest diagnostics

struct CatalogPDFBlockClassificationDiagnostics: Sendable, Codable {
    let totalBlocks: Int
    let blocksByType: [String: Int]
    let programCandidates: Int
    let programAccepted: Int
    let programRejected: Int
    let sampleRejections: [String]
    let sampleAcceptedEvidence: [String]
    let averageAcceptedProgramConfidence: Double?
}

struct CatalogPDFIngestOutput: Sendable {
    let programs: [ScrapedProgram]
    let courses: [CatalogCourse]
    let requirements: [DegreeRequirement]
    let policyRows: [(sourceURL: String, navTitle: String, sectionHeading: String?, bodyText: String, catalogScope: String, contentHash: String, binding: String?)]
    let healthReport: CatalogPDFHealthReport
    let foundation: CatalogPDFFoundationResult
    let classificationDiagnostics: CatalogPDFBlockClassificationDiagnostics
    let ocrPagesUsed: Int
    let documentIR: CatalogDocumentIR?
}

struct CatalogPDFFoundationResult: Sendable {
    let pageCount: Int
    let sections: [CatalogPDFDocumentSection]
}
