// CatalogPDFProfile.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFHeadingRules.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogPDFHeadingRules: Codable, Sendable {
    let allCapsMaxLength: Int?
    let headingPrefixes: [String]?
}

struct CatalogPDFBlockRules: Codable, Sendable {
    let programMinConfidence: Float?
    let courseMinConfidence: Float?
    let programPositivePatterns: [String]?
    let courseCodePatterns: [String]?
}

struct CatalogPDFProfileData: Codable, Sendable {
    let schoolID: String
    let courseCodePatterns: [String]
    let headingRules: CatalogPDFHeadingRules?
    let blockRules: CatalogPDFBlockRules?
}

enum CatalogPDFProfileLoader {
    private static let bundledIDs: [String: String] = [
        "fordham_university": "fordham",
        "carnegie_mellon_university": "cmu",
        "brooklyn_college": "brooklyn",
    ]

    static func profile(forSchoolID schoolID: String) -> CatalogPDFProfileData {
        let key = bundledIDs[schoolID] ?? schoolID
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-").first ?? schoolID

        if let loaded = loadBundled(named: key) {
            return loaded
        }
        return defaultProfile(schoolID: schoolID)
    }

    private static func loadBundled(named name: String) -> CatalogPDFProfileData? {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Catalog/PDF/Profiles"),
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Profiles"),
            Bundle.main.url(forResource: name, withExtension: "json"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let profile = try? JSONDecoder().decode(CatalogPDFProfileData.self, from: data) {
                return profile
            }
        }
        return builtinProfiles[name]
    }

    private static let builtinProfiles: [String: CatalogPDFProfileData] = [
        "fordham": CatalogPDFProfileData(
            schoolID: "fordham_university",
            courseCodePatterns: [#"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#],
            headingRules: CatalogPDFHeadingRules(allCapsMaxLength: 55, headingPrefixes: ["Chapter", "Section"]),
            blockRules: CatalogPDFBlockRules(
                programMinConfidence: 0.68,
                courseMinConfidence: 0.55,
                programPositivePatterns: [
                    #"(?i)\b(bachelor|master|associate)\b"#,
                    #"(?i)\b(B\.?A\.?|B\.?S\.?|M\.?A\.?|M\.?S\.?)\b"#,
                    #"(?i)\bminor in\b"#,
                ],
                courseCodePatterns: [#"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#]
            )
        ),
        "cmu": CatalogPDFProfileData(
            schoolID: "carnegie_mellon_university",
            courseCodePatterns: [#"\b([0-9]{2})[-–]([0-9]{3})\b"#, #"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#],
            headingRules: CatalogPDFHeadingRules(allCapsMaxLength: 70, headingPrefixes: nil),
            blockRules: CatalogPDFBlockRules(
                programMinConfidence: 0.65,
                courseMinConfidence: 0.55,
                programPositivePatterns: [#"(?i)\b(B\.?S\.?|B\.?A\.?)\b"#, #"(?i)\bminor\b"#],
                courseCodePatterns: [#"\b([0-9]{2})[-–]([0-9]{3})\b"#]
            )
        ),
        "brooklyn": CatalogPDFProfileData(
            schoolID: "brooklyn_college",
            courseCodePatterns: [#"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#],
            headingRules: CatalogPDFHeadingRules(allCapsMaxLength: 60, headingPrefixes: nil),
            blockRules: CatalogPDFBlockRules(
                programMinConfidence: 0.65,
                courseMinConfidence: 0.55,
                programPositivePatterns: [#"(?i)\b(bachelor|associate)\b"#, #"(?i)\bminor\b"#],
                courseCodePatterns: [#"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#]
            )
        ),
    ]

    private static func defaultProfile(schoolID: String) -> CatalogPDFProfileData {
        CatalogPDFProfileData(
            schoolID: schoolID,
            courseCodePatterns: [#"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#],
            headingRules: CatalogPDFHeadingRules(allCapsMaxLength: 60, headingPrefixes: nil),
            blockRules: CatalogPDFBlockRules(
                programMinConfidence: 0.65,
                courseMinConfidence: 0.55,
                programPositivePatterns: nil,
                courseCodePatterns: nil
            )
        )
    }

    static func programMinConfidence(for schoolID: String) -> Float {
        profile(forSchoolID: schoolID).blockRules?.programMinConfidence ?? 0.65
    }

    static func courseMinConfidence(for schoolID: String) -> Float {
        profile(forSchoolID: schoolID).blockRules?.courseMinConfidence ?? 0.55
    }
}
