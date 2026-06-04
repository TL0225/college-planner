// ProgramListSerialization.swift
// Feature: Profile
// Purpose: Profile module — ProgramListSerialization.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Encodes multi-select program names (majors/minors) without breaking on commas inside labels like `Cyber Defense, M.S.`
enum ProgramListSerialization {
    private static let recordSeparator = "\u{1E}"

    static func encode(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        if let data = try? JSONEncoder().encode(cleaned),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return cleaned.joined(separator: recordSeparator)
    }

    static func decode(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONDecoder().decode([String].self, from: data) {
                return json
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        if trimmed.contains(recordSeparator) {
            return trimmed
                .split(separator: Character(recordSeparator), omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return mergeLegacyCommaSeparatedParts(
            trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    /// Rebuilds list from legacy `major` / `secondaryMajor` columns and comma-joined strings.
    static func majorsFromLegacyProfile(major: String?, secondaryMajor: String?) -> [String] {
        var out: [String] = []

        let primary = (major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            if primary.contains(",") {
                out.append(contentsOf: mergeLegacyCommaSeparatedParts(
                    primary.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
            } else {
                out.append(primary)
            }
        }

        let secondary = (secondaryMajor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondary.isEmpty {
            if out.count == 1, isLikelyDegreeTypeSuffix(secondary) {
                out[0] = displayLabel(programName: out[0], degreeType: secondary)
            } else if !out.contains(where: { $0.caseInsensitiveCompare(secondary) == .orderedSame }) {
                out.append(secondary)
            }
        }

        return coalesceProgramList(dedupePreservingOrder(out))
    }

    /// UI label for a catalog program: `Cyber Defense (M.S.)` — avoids comma delimiters in stored lists.
    static func displayLabel(programName: String, degreeType: String?) -> String {
        var name = programName
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let degreeType, !degreeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return name
        }

        let token = degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("/") { return name }

        let parenSuffix = "(\(token))"
        if name.hasSuffix(parenSuffix) { return name }

        let commaSuffix = ", \(token)"
        if name.hasSuffix(commaSuffix) {
            let base = String(name.dropLast(commaSuffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return base.isEmpty ? name : "\(base) (\(token))"
        }

        if let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close {
            let inner = name[name.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizeDegreeToken(inner) == normalizeDegreeToken(token) {
                return name
            }
        }

        return "\(name) (\(token))"
    }

    static func mergeLegacyCommaSeparatedParts(_ parts: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < parts.count {
            var combined = parts[index]
            var next = index + 1
            while next < parts.count, isLikelyDegreeTypeSuffix(parts[next]) {
                combined = "\(combined), \(parts[next])"
                next += 1
            }
            result.append(combined.trimmingCharacters(in: .whitespacesAndNewlines))
            index = next
        }
        return result.filter { !$0.isEmpty }
    }

    static func isLikelyDegreeTypeSuffix(_ raw: String) -> Bool {
        DegreeTokenRegistry.isLikelyDegreeTypeSuffix(raw)
    }

    private static func normalizeDegreeToken(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Merges stray degree-type tokens saved as separate list entries (e.g. `Cyber Defense` + `M.S.`).
    static func coalesceProgramList(_ values: [String]) -> [String] {
        var out: [String] = []
        var index = 0
        while index < values.count {
            var name = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
            var next = index + 1
            while next < values.count, isLikelyDegreeTypeSuffix(values[next]) {
                name = displayLabel(programName: name, degreeType: values[next])
                next += 1
            }
            if !name.isEmpty {
                out.append(name)
            }
            index = next
        }
        return dedupePreservingOrder(out)
    }

    private static func dedupePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                out.append(value)
            }
        }
        return out
    }
}
