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
    case exceededMaxPDFSize(actualBytes: Int, limitBytes: Int)
    case exceededMaxPageCount(actual: Int, limit: Int)
    case exceededMaxProcessingTime(seconds: TimeInterval)

    var failureClass: CatalogPDFFailureClass {
        switch self {
        case .fileNotFound, .exceededMaxPDFSize:
            return .download
        case .failedToOpenPDF:
            return .corruption
        case .extractedEmptyText, .exceededMaxPageCount, .exceededMaxProcessingTime:
            return .extraction
        case .noProgramsExtracted, .noCoursesExtracted:
            return .entityExtraction
        }
    }

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
        case .exceededMaxPDFSize(let actualBytes, let limitBytes):
            let actualMB = Double(actualBytes) / 1_048_576.0
            let limitMB = Double(limitBytes) / 1_048_576.0
            return String(format: "Catalog PDF exceeds size limit (%.1f MB > %.1f MB).", actualMB, limitMB)
        case .exceededMaxPageCount(let actual, let limit):
            return "Catalog PDF exceeds page limit (\(actual) > \(limit))."
        case .exceededMaxProcessingTime(let seconds):
            return "Catalog PDF parsing exceeded time limit (\(Int(seconds))s)."
        }
    }
}
