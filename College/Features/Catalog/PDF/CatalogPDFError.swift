// CatalogPDFError.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFError.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Errors for catalog bulletin PDF parsing (not syllabus upload).
enum CatalogPDFError: LocalizedError, Sendable {
    case fileNotFound
    case failedToOpenPDF
    case extractedEmptyText
    case noProgramsExtracted
    case noCoursesExtracted

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Catalog PDF could not be found."
        case .failedToOpenPDF:
            return "Could not open the catalog PDF."
        case .extractedEmptyText:
            return "Could not extract any text from this catalog PDF."
        case .noProgramsExtracted:
            return "No programs were extracted from the catalog PDF after block classification."
        case .noCoursesExtracted:
            return "No courses were extracted from the catalog PDF."
        }
    }
}
