// CatalogBundle.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleEnvelope.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - On-disk signed envelope

struct CatalogBundleEnvelope: Codable, Sendable {
    static let signatureVersion = "2"
    static let algorithm = "Ed25519"

    let signatureVersion: String
    let algorithm: String
    let payloadHash: String
    let signature: String
    let signerPublicKey: String
    let signerFingerprint: String
    let payloadJSON: String
}

// MARK: - Payload

struct CatalogBundle: Codable, Sendable {
    static let fileExtension = "collegecatalog"
    static let currentVersion = "1.0"

    let bundleVersion: String
    let exportedAt: Date
    let schoolName: String
    let catalogURL: String?
    let catalogFormat: String?
    let departments: [BundledDepartment]
    let courses: [CatalogCourse]
    let programs: [BundledProgram]
    let requirementSections: [BundledRequirementSection]
    let scrapeStates: [BundledScrapeState]
}

struct BundledDepartment: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let code: String?
    let school: String?
}

struct BundledProgram: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let degreeLevel: String
    let degreeType: String?
    let isMinor: Bool
    let programURL: String?
    let programURLs: String?
    let sourceCatoids: String?
    let resolvedDepartment: String?
    let resolvedCollege: String?
    let mappingConfidence: Double?
    let mappingSource: String?
    let departmentNames: [String]
}

struct BundledRequirementSection: Codable, Sendable, Identifiable {
    let id: UUID
    let programName: String?
    let programPoid: String?
    let totalCreditsRequired: Int?
    let requirementGroupsJSON: String?
    let degreeType: String
    let major: String
    let programURL: String?
    let requirementCategory: String
    let sectionOrder: Int
    let requiredCourses: String?
    let requiredCoursesDetailedJSON: String?
    let selectFromJSON: String?
    let selectFromDetailedJSON: String?
    let selectCount: Int?
    let creditsRequired: Int
    let descriptionText: String?
    let requirementsHash: String?
    let lastScrapedAt: Date?
}

struct BundledScrapeState: Codable, Sendable {
    let catoid: String
    let catalogTitle: String?
    let courseCount: Int
    let lastScrapedAt: Date
}

// MARK: - Trust & local catalog metadata

struct TrustedCatalogSource: Codable, Sendable, Identifiable {
    var id: String { fingerprint }
    let publicKeyBase64: String
    let fingerprint: String
    let label: String?
    let trustedAt: Date
}

struct LocalCatalogInfo: Sendable {
    let schoolName: String
    let fileURL: URL
    let fileSize: Int64
    let lastModified: Date
    let signerFingerprint: String?
}

struct CatalogBundleImportSummary: Sendable {
    let schoolName: String
    let courseCount: Int
    let programCount: Int
    let requirementSectionCount: Int
    let exportedAt: Date
    let signerFingerprint: String
    let wasTrustedSource: Bool
}

// MARK: - Filename helpers

enum CatalogBundleNaming {
    static func sanitizedSchoolName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let replaced = name
            .replacingOccurrences(of: " ", with: "_")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
        return String(replaced).replacingOccurrences(of: "__", with: "_")
    }

    static func canonicalFilename(for schoolName: String) -> String {
        "\(sanitizedSchoolName(schoolName))_catalog.\(CatalogBundle.fileExtension)"
    }

    static func shareableFilename(for schoolName: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        return "\(sanitizedSchoolName(schoolName))_catalog_\(dateStr).\(CatalogBundle.fileExtension)"
    }
}

// MARK: - Base64url

enum CatalogBundleBase64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
