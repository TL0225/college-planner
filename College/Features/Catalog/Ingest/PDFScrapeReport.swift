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
    let warnings: [String]

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
