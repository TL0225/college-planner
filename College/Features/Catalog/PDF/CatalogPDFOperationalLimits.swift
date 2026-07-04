// CatalogPDFOperationalLimits.swift
// Feature: Catalog
// Purpose: Hard resource budgets for catalog PDF ingest.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Operational safeguards for catalog PDF download and parsing.
enum CatalogPDFOperationalLimits {
    static let defaultMaxPDFSizeMB = 250
    static let defaultMaxPageCount = 3_000
    static let defaultMaxOCRPages = 200
    static let defaultMaxProcessingTimeSeconds = 600

    static var maxPDFSizeBytes: Int {
        let mb = UserDefaults.standard.object(forKey: "catalog.pdf.maxSizeMB") as? Int ?? defaultMaxPDFSizeMB
        return max(1, mb) * 1_048_576
    }

    static var maxPageCount: Int {
        let value = UserDefaults.standard.object(forKey: "catalog.pdf.maxPageCount") as? Int ?? defaultMaxPageCount
        return max(1, value)
    }

    static var maxOCRPages: Int {
        let value = UserDefaults.standard.object(forKey: "catalog.pdf.maxOCRPages") as? Int ?? defaultMaxOCRPages
        return max(0, value)
    }

    static var maxProcessingTimeSeconds: TimeInterval {
        let value = UserDefaults.standard.object(forKey: "catalog.pdf.maxProcessingTimeSeconds") as? Int
            ?? defaultMaxProcessingTimeSeconds
        return TimeInterval(max(30, value))
    }

    static func validateCachedFileSize(at url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxPDFSizeBytes else {
            throw CatalogPDFError.exceededMaxPDFSize(actualBytes: size, limitBytes: maxPDFSizeBytes)
        }
    }

    static func validatePageCount(_ pageCount: Int) throws {
        guard pageCount <= maxPageCount else {
            throw CatalogPDFError.exceededMaxPageCount(actual: pageCount, limit: maxPageCount)
        }
    }
}
