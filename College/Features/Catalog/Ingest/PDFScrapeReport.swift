// PDFScrapeReport.swift
// Feature: Catalog
// Purpose: Catalog module — PDFScrapeReport.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Diagnostics emitted after PDF ingest for Settings / power-user review.
struct PDFScrapeReport: Codable, Sendable {
    let schoolID: String
    let schoolName: String
    let generatedAt: Date
    let parserVersion: String
    let pdfSHA256: String
    let pageCount: Int
    let programsExtracted: Int
    let coursesExtracted: Int
    let requirementsExtracted: Int
    let policiesExtracted: Int
    let healthReport: PDFHealthReport?
    let blockClassification: CatalogPDFBlockClassificationDiagnostics?
    let parserCapabilityVersion: String?
    let ocrPagesUsed: Int?
    let averageProgramConfidence: Double?
    let layoutProfileID: String?
    let documentIRNodeCount: Int?
    let warnings: [String]
    let failureClass: CatalogPDFFailureClass?
    let lastFailureMessage: String?

    init(
        schoolID: String,
        schoolName: String,
        generatedAt: Date,
        parserVersion: String,
        pdfSHA256: String,
        pageCount: Int,
        programsExtracted: Int,
        coursesExtracted: Int,
        requirementsExtracted: Int,
        policiesExtracted: Int,
        healthReport: PDFHealthReport?,
        blockClassification: CatalogPDFBlockClassificationDiagnostics?,
        parserCapabilityVersion: String?,
        ocrPagesUsed: Int?,
        averageProgramConfidence: Double?,
        layoutProfileID: String?,
        documentIRNodeCount: Int?,
        warnings: [String],
        failureClass: CatalogPDFFailureClass? = nil,
        lastFailureMessage: String? = nil
    ) {
        self.schoolID = schoolID
        self.schoolName = schoolName
        self.generatedAt = generatedAt
        self.parserVersion = parserVersion
        self.pdfSHA256 = pdfSHA256
        self.pageCount = pageCount
        self.programsExtracted = programsExtracted
        self.coursesExtracted = coursesExtracted
        self.requirementsExtracted = requirementsExtracted
        self.policiesExtracted = policiesExtracted
        self.healthReport = healthReport
        self.blockClassification = blockClassification
        self.parserCapabilityVersion = parserCapabilityVersion
        self.ocrPagesUsed = ocrPagesUsed
        self.averageProgramConfidence = averageProgramConfidence
        self.layoutProfileID = layoutProfileID
        self.documentIRNodeCount = documentIRNodeCount
        self.warnings = warnings
        self.failureClass = failureClass
        self.lastFailureMessage = lastFailureMessage
    }

    static let storageKeyPrefix = "catalog.pdf.scrapeReport.v1."

    static func load(schoolID: String) -> PDFScrapeReport? {
        guard let data = UserDefaults.standard.data(forKey: storageKeyPrefix + schoolID) else { return nil }
        return try? JSONDecoder().decode(PDFScrapeReport.self, from: data)
    }

    static func save(_ report: PDFScrapeReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: storageKeyPrefix + report.schoolID)
    }
}
