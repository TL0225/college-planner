// AcademicProgramHelpers.swift
// Feature: Academics
// Purpose: Academics module — RequirementFingerprint.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// Shared program-name / degree-type helpers (Phase 7f — extracted from legacy local store).
enum AcademicProgramHelpers {
    private struct RequirementFingerprint: Codable {
        let order: Int
        let category: String
        let requiredCourses: [String]?
        let requiredCoursesDetailed: [CourseDetail]?
        let selectFrom: [String]?
        let selectFromDetailed: [CourseDetail]?
        let selectCount: Int?
        let creditsRequired: Int
        let description: String?
    }

    static func stableRequirementsHash(_ requirements: [DegreeRequirement]) -> String {
        let normalized: [RequirementFingerprint] = requirements.enumerated().map { index, requirement in
            RequirementFingerprint(
                order: index,
                category: requirement.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                requiredCourses: requirement.requiredCourses?.map(normalizeCourseCodeForProgress).sorted(),
                requiredCoursesDetailed: requirement.requiredCoursesDetailed?.sorted(by: { $0.code < $1.code }),
                selectFrom: requirement.selectFrom?.map(normalizeCourseCodeForProgress).sorted(),
                selectFromDetailed: requirement.selectFromDetailed?.sorted(by: { $0.code < $1.code }),
                selectCount: requirement.selectCount,
                creditsRequired: requirement.creditsRequired,
                description: requirement.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(normalized)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cleanedProgramNameFromDisplay(_ display: String, profileDegreeType: String? = nil) -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        if let open = trimmed.lastIndex(of: "("),
           let close = trimmed.lastIndex(of: ")"),
           open < close,
           close == trimmed.index(before: trimmed.endIndex) {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty, !inner.isEmpty {
                if inner.caseInsensitiveCompare("Minor") == .orderedSame {
                    return trimmed
                }
                let norm = DegreeTokenRegistry.normalizeToken(inner)
                if DegreeTokenRegistry.isKnownToken(norm)
                    || DegreeTokenRegistry.isLikelyDegreeTypeSuffix(norm) {
                    return base
                }
            }
        }

        if let comma = trimmed.lastIndex(of: ",") {
            let suffix = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }

        let dtRaw = (profileDegreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = degreeTypeCandidates(from: dtRaw)
        guard !candidates.isEmpty else { return trimmed }

        let parts = trimmed.split(separator: " ")
        guard parts.count >= 2 else { return trimmed }
        let last = String(parts.last ?? "")
        guard last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil else { return trimmed }

        func normalizeToken(_ s: String) -> String {
            s.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        }

        let lastNorm = normalizeToken(last)
        if candidates.contains(where: { normalizeToken($0) == lastNorm }) {
            return parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
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

        var seen = Set<String>()
        var out: [String] = []
        for candidate in candidates {
            let token = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty || seen.contains(token) { continue }
            seen.insert(token)
            out.append(token)
        }
        return out
    }

    static func mergedDegreeTypeCandidates(majorDisplay: String, profileDegreeType: String?) -> [String] {
        var candidates: [String] = []
        let displayTokens = CatalogDegreeTypeFilter.strictFilterTokens(forPickerValue: majorDisplay)
        for token in displayTokens.sorted(by: { $0.count > $1.count }) {
            candidates.append(token)
            if let entry = DegreeTokenRegistry.entry(forNormalizedToken: token) {
                candidates.append(entry.fullLabel)
            }
        }
        let profileRaw = (profileDegreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(contentsOf: degreeTypeCandidates(from: profileRaw))
        if !profileRaw.isEmpty, !candidates.contains(profileRaw) {
            candidates.insert(profileRaw, at: 0)
        }
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    static func canonicalizeAcalogURL(_ urlString: String, removingQueryItems: Set<String> = ["returnto"]) -> String {
        let cleaned = urlString
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        guard var components = URLComponents(string: cleaned) else { return cleaned }

        let remove = Set(removingQueryItems.map { $0.lowercased() })
        if let items = components.queryItems, !items.isEmpty {
            let filtered = items
                .filter { !remove.contains($0.name.lowercased()) }
                .sorted {
                    let aName = $0.name.lowercased()
                    let bName = $1.name.lowercased()
                    if aName != bName { return aName < bName }
                    return ($0.value ?? "").lowercased() < ($1.value ?? "").lowercased()
                }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        components.fragment = nil
        return components.string ?? cleaned
    }

    static func decodeJSONCourseList(_ json: String?) -> [String] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func decodeDetailedCourseList(_ json: String?) -> [CourseDetail]? {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([CourseDetail].self, from: data)
    }

    static func encodeJSONCourseList(_ codes: [String]) -> String? {
        let cleaned = codes
            .map { normalizeCourseCodeForProgress($0) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty,
              let data = try? JSONEncoder().encode(cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encodeDetailedCourseList(_ courses: [CourseDetail]) -> String? {
        guard let data = try? JSONEncoder().encode(courses) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func normalizeCourseCodeForProgress(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
    }

    static func isLetterGradedForGPA(_ gradingType: String?) -> Bool {
        let token = (gradingType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return true }
        return token.caseInsensitiveCompare("Letter Grade") == .orderedSame
    }

    static func gradePoints(for grade: String) -> Double? {
        let g = grade.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch g {
        case "A+", "A": return 4.0
        case "A-": return 3.7
        case "B+": return 3.3
        case "B": return 3.0
        case "B-": return 2.7
        case "C+": return 2.3
        case "C": return 2.0
        case "C-": return 1.7
        case "D+": return 1.3
        case "D": return 1.0
        case "D-": return 0.7
        case "F": return 0.0
        default: return nil
        }
    }

    static func graduationSeasonOrder(for season: String) -> Int16 {
        switch season.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "spring": return 0
        case "summer": return 1
        case "fall": return 2
        case "winter": return 3
        default: return 4
        }
    }

    static func canonicalGraduationSeasonLabel(_ season: String) -> String {
        let trimmed = season.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "spring": return "Spring"
        case "summer": return "Summer"
        case "fall": return "Fall"
        case "winter": return "Winter"
        default: return trimmed
        }
    }
}
