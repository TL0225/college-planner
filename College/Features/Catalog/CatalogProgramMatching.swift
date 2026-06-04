// CatalogProgramMatching.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogProgramMatching.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Program department / degree-type matching helpers (local store catalog reads).
enum CatalogProgramMatching {
    static func programDepartmentKeysMatch(_ input: String, candidate: String) -> Bool {
        if input.isEmpty || candidate.isEmpty { return false }
        if input == candidate { return true }
        let shorter = input.count <= candidate.count ? input : candidate
        let longer = input.count > candidate.count ? input : candidate
        guard shorter.count >= 5 else { return false }
        return longer == shorter || longer.hasPrefix(shorter + " ") || longer.hasSuffix(" " + shorter)
    }

    static func normalizeProgramDepartmentKey(_ value: String) -> String {
        var normalized = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let removeList = [
            " department page",
            " department",
            " program",
            " office",
            " page"
        ]
        for term in removeList where normalized.hasSuffix(term) {
            normalized = String(normalized.dropLast(term.count))
        }
        if normalized.hasPrefix("department of ") {
            normalized = String(normalized.dropFirst("department of ".count))
        }

        return normalized
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func degreeTypeCandidates(from raw: String) -> [String] {
        var candidates: [String] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        candidates.append(trimmed)

        let splitParts = trimmed
            .replacingOccurrences(of: " ", with: "")
            .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
            .map { String($0) }
            .filter { !$0.isEmpty }
        if splitParts.count >= 2 {
            candidates.append(contentsOf: splitParts)
        }

        if let open = trimmed.firstIndex(of: "("), let close = trimmed.firstIndex(of: ")"), open < close {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
            let parts = inner
                .replacingOccurrences(of: " ", with: "")
                .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == ";" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            candidates.append(contentsOf: parts)
        }

        let normalized = trimmed
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        if !normalized.isEmpty {
            candidates.append(normalized)
            let normalizedSplit = normalized
                .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if normalizedSplit.count >= 2 {
                candidates.append(contentsOf: normalizedSplit)
            }
        }

        if let canonical = DegreeTypeNormalizer.normalize(trimmed) {
            candidates.append(canonical.storageToken)
            candidates.append(canonical.displayLabel)
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }
}
