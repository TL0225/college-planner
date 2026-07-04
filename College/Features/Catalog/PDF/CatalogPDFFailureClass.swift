// CatalogPDFFailureClass.swift
// Feature: Catalog
// Purpose: Failure taxonomy for catalog PDF ingest observability.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPDFFailureClass: String, Codable, Sendable {
    case download
    case corruption
    case extraction
    case classification
    case entityExtraction
    case persistence
    case operationalLimit
}
