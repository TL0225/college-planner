// CatalogParserCapability.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogParserCapability.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogParserCapability {
    static let version = "2026.06.v1"

    enum OCRPolicy: String, Codable, Sendable {
        case automatic
        case always
        case never
    }

    static func ocrPolicy(for schoolID: String) -> OCRPolicy {
        let perSchoolKey = "catalog.pdf.ocr.policy.\(schoolID)"
        if let raw = UserDefaults.standard.string(forKey: perSchoolKey),
           let policy = OCRPolicy(rawValue: raw) {
            return policy
        }
        let globalKey = "catalog.pdf.ocr.policy.default"
        if let raw = UserDefaults.standard.string(forKey: globalKey),
           let policy = OCRPolicy(rawValue: raw) {
            return policy
        }
        return .automatic
    }
}
