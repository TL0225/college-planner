// CatalogSchoolTier.swift
// Feature: Catalog
// Purpose: Development / Validation / Held-Out school tiers (P13).

import Foundation

enum CatalogSchoolTier: String, Codable, Sendable, CaseIterable {
    case development
    case validation
    case heldOut

    var displayName: String {
        switch self {
        case .development: return "Development"
        case .validation: return "Validation"
        case .heldOut: return "Held-Out"
        }
    }
}

enum CatalogSchoolTierRegistry {
    private static let development: Set<String> = [
        "fordham_university",
        "carnegie_mellon_university",
    ]
    private static let validation: Set<String> = [
        "brooklyn_college_undergraduate",
        "brooklyn_college_graduate",
    ]

    static func tier(for schoolID: String) -> CatalogSchoolTier {
        let normalized = schoolID.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if development.contains(normalized) { return .development }
        if validation.contains(normalized) { return .validation }
        return .heldOut
    }

    static func schools(in tier: CatalogSchoolTier) -> [String] {
        switch tier {
        case .development: return Array(development).sorted()
        case .validation: return Array(validation).sorted()
        case .heldOut: return []
        }
    }

    static func universalScoreWeight(for tier: CatalogSchoolTier) -> Double {
        switch tier {
        case .development: return 0.2
        case .validation: return 0.3
        case .heldOut: return 0.5
        }
    }
}
