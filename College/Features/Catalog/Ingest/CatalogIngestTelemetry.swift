// CatalogIngestTelemetry.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIngestTelemetrySession.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogIngestAnomalyKind: String, Codable, Sendable, CaseIterable {
    case zeroCoursesFromCourseIndex
    case classificationMismatch
    case selectorDrift
    case archiveYearCollision
    case unexpectedContentType
}

struct CatalogIngestTelemetrySession: Codable, Sendable {
    let schoolID: String
    let source: String
    let startedAt: Date
    let endedAt: Date
    let pagesDiscovered: Int
    let pagesClassified: Int
    let coursesExtracted: Int
    let programsExtracted: Int
    let anomalies: [CatalogIngestAnomalyKind]
}
