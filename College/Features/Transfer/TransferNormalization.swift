// TransferNormalization.swift
// Feature: Transfer
// Purpose: Transfer Database — deterministic dedupe-key construction for equivalencies.
// Data: Pure transforms; reuses CatalogImportTransforms.normalizeCourseCode.

import Foundation

/// Pure helpers for deduplicating equivalencies that describe the same source→target pairing.
enum TransferNormalization {
    /// Stable identity for a single source→target course mapping, independent of provenance.
    ///
    /// Two equivalencies that share a dedupe key are treated as the same fact (and merged as
    /// corroborating evidence) even if they came from different sources.
    static func dedupeKey(
        sourceSchoolID: String,
        sourceCourseCode: String,
        targetSchoolID: String,
        targetCourseCode: String,
        degreeLevel: String
    ) -> String {
        let parts = [
            normalizeSchoolID(sourceSchoolID),
            CatalogImportTransforms.normalizeCourseCode(sourceCourseCode),
            normalizeSchoolID(targetSchoolID),
            CatalogImportTransforms.normalizeCourseCode(targetCourseCode),
            normalizeDegreeLevel(degreeLevel),
        ]
        return parts.joined(separator: "|")
    }

    /// Convenience overload working directly off a DTO.
    static func dedupeKey(for dto: TransferEquivalencyDTO) -> String {
        dedupeKey(
            sourceSchoolID: dto.sourceSchoolID,
            sourceCourseCode: dto.sourceCourseCode,
            targetSchoolID: dto.targetSchoolID,
            targetCourseCode: dto.targetCourseCode,
            degreeLevel: dto.degreeLevel
        )
    }

    /// Composite origin identifier stored on the model (`sourceKind:externalID`).
    static func originIdentifier(kind: TransferSourceKind, externalID: String) -> String {
        let trimmed = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.rawValue : "\(kind.rawValue):\(trimmed)"
    }

    /// Inverse of `originIdentifier(kind:externalID:)`.
    static func decodeOrigin(_ identifier: String) -> (kind: TransferSourceKind, externalID: String) {
        guard let separatorIndex = identifier.firstIndex(of: ":") else {
            let kind = TransferSourceKind(rawValue: identifier) ?? .manualEntry
            return (kind, "")
        }
        let rawKind = String(identifier[identifier.startIndex..<separatorIndex])
        let externalID = String(identifier[identifier.index(after: separatorIndex)...])
        let kind = TransferSourceKind(rawValue: rawKind) ?? .manualEntry
        return (kind, externalID)
    }

    static func normalizeSchoolID(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func normalizeDegreeLevel(_ raw: String) -> String {
        let cleaned = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch cleaned {
        case "grad", "graduate", "masters", "master", "phd", "doctoral":
            return "graduate"
        case "", "ug", "undergrad", "undergraduate", "bachelor", "bachelors":
            return "undergraduate"
        default:
            return cleaned
        }
    }
}
