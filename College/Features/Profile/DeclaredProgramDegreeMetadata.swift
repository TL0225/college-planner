// DeclaredProgramDegreeMetadata.swift
// Feature: Profile
// Purpose: Profile module — Inference.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Infers `degreeType` / `degreeLevel` from declared program labels such as `Cyber Defense (M.S.)`.
enum DeclaredProgramDegreeMetadata {
    struct Inference: Equatable {
        let token: String
        let fullDegreeType: String
        let degreeLevel: String
    }

    static func infer(fromProgramDisplays displays: [String]) -> Inference? {
        for display in displays {
            if let inference = infer(fromProgramDisplay: display) {
                return inference
            }
        }
        return nil
    }

    static func infer(fromProgramDisplay display: String) -> Inference? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = CatalogDegreeTypeFilter.strictFilterTokens(forPickerValue: trimmed)
        if tokens.count >= 2 {
            return nil
        }
        guard let token = tokens.max(by: { $0.count < $1.count }) else { return nil }
        guard ProgramListSerialization.isLikelyDegreeTypeSuffix(token) else { return nil }

        guard let full = fullDegreeType(matchingNormalizedToken: token) else { return nil }
        let level = DegreeConfiguration.level(for: full) ?? levelForNormalizedToken(token)
        return Inference(token: token, fullDegreeType: full, degreeLevel: level)
    }

    /// Resolution order: suffix on program title → catalog row → stored profile value.
    static func effectiveMetadata(
        majors: [String],
        storedDegreeType: String?,
        storedDegreeLevel: String?,
        catalogFallback: ((String) -> String?)?
    ) -> Inference? {
        if let inferred = infer(fromProgramDisplays: majors) {
            return inferred
        }

        if let catalogFallback {
            for display in majors {
                let cleaned = cleanedProgramName(from: display)
                guard !cleaned.isEmpty else { continue }
                if let catalogType = catalogFallback(cleaned),
                   let canonical = DegreeTypeNormalizer.normalize(catalogType) {
                    return inference(from: canonical)
                }
            }
        }

        let stored = (storedDegreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, let canonical = DegreeTypeNormalizer.normalize(stored) {
            return inference(from: canonical)
        }

        return nil
    }

    static func shouldUpdateStoredDegreeType(current: String?, inferred: Inference) -> Bool {
        let stored = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if stored.isEmpty { return true }

        let storedTokens = CatalogDegreeTypeFilter.strictFilterTokens(forPickerValue: stored)
        if storedTokens.contains(inferred.token) { return false }

        let storedGrad = storedTokens.contains(where: isGraduateNormalizedToken)
        let inferredGrad = isGraduateNormalizedToken(inferred.token)
        if storedGrad != inferredGrad { return true }

        return !storedTokens.contains(inferred.token)
    }

    static func isGraduateProgramDisplay(_ display: String) -> Bool {
        guard let inference = infer(fromProgramDisplays: [display]) else { return false }
        return !DegreeConfiguration.isUndergraduate(inference.degreeLevel)
    }

    static func shouldShowMinorPrograms(degreeLevel: String?, minors: [String]) -> Bool {
        guard !minors.isEmpty else { return false }
        let level = (degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if level.isEmpty { return true }
        return DegreeConfiguration.isUndergraduate(level)
    }

    static func fullDegreeType(matchingNormalizedToken token: String) -> String? {
        let norm = CatalogDegreeTypeFilter.normalizeToken(token)
        guard !norm.isEmpty else { return nil }

        if let entry = DegreeTokenRegistry.entry(forNormalizedToken: norm) {
            return entry.fullLabel
        }

        for level in DegreeConfiguration.degreeLevels {
            for type in level.types {
                let short = CatalogDegreeTypeFilter.normalizeToken(DegreeConfiguration.shortForm(from: type))
                if short == norm { return type }
            }
        }
        return nil
    }

    private static func inference(from canonical: CanonicalDegreeType) -> Inference? {
        let token = canonical.token ?? canonical.storageToken
        let full = canonical.fullLabel ?? fullDegreeType(matchingNormalizedToken: token) ?? token
        guard !full.isEmpty else { return nil }
        return Inference(token: token, fullDegreeType: full, degreeLevel: canonical.degreeLevel)
    }

    private static func cleanedProgramName(from display: String) -> String {
        display.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func levelForNormalizedToken(_ token: String) -> String {
        let norm = CatalogDegreeTypeFilter.normalizeToken(token)
        if let entry = DegreeTokenRegistry.entry(forNormalizedToken: norm) {
            return entry.degreeLevel
        }
        if norm.hasPrefix("B") || norm == "AA" || norm == "AS" || norm == "AAS" {
            return DegreeConfiguration.undergraduate
        }
        if norm.hasPrefix("M") { return DegreeConfiguration.graduate }
        if norm.contains("PHD") { return DegreeConfiguration.doctorateProfessional }
        if norm == "JD" { return DegreeConfiguration.lawSchool }
        if norm == "MD" { return DegreeConfiguration.medicalSchool }
        if norm == "DDS" || norm == "DMD" { return DegreeConfiguration.dentalSchool }
        return DegreeConfiguration.graduate
    }

    private static func isGraduateNormalizedToken(_ token: String) -> Bool {
        let norm = CatalogDegreeTypeFilter.normalizeToken(token)
        if norm.hasPrefix("B") || norm == "AA" || norm == "AS" || norm == "AAS" { return false }
        if norm.hasPrefix("M") { return true }
        if norm.contains("PHD") || ["JD", "MD", "DDS", "DMD", "DPT", "PHARMD", "DNP", "DVM", "DO", "OD", "DC"].contains(norm) {
            return true
        }
        return false
    }
}
