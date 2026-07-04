// CareerResumeStructuredParsePipeline.swift
// Feature: Career / ResumeParsing
// Purpose: Heuristic-first resume parse with optional Foundation Models refinement.

import Foundation

enum CareerResumeStructuredParsePipeline {
    /// Parses resume text using offline heuristics, then refines with on-device AI when available.
    static func parse(plainText: String) async -> CareerResumeStructuredProfile {
        let normalized = CareerResumePlainTextNormalizer.normalize(plainText)
        let heuristic = CareerResumeStructuredParser.parse(plainText: normalized)
        let merged: CareerResumeStructuredProfile
        if let llm = await CareerResumeLLMStructuredParser.parse(plainText: normalized) {
            merged = merge(heuristic: heuristic, llm: llm)
        } else {
            merged = heuristic
        }
        return CareerResumeParseSanitizer.sanitize(merged, sourceText: normalized)
    }

    static func merge(
        heuristic: CareerResumeStructuredProfile,
        llm: CareerResumeStructuredProfile
    ) -> CareerResumeStructuredProfile {
        var merged = llm

        merged.name = llm.name ?? heuristic.name
        merged.email = llm.email ?? heuristic.email
        merged.phone = llm.phone ?? heuristic.phone
        merged.location = llm.location ?? heuristic.location
        merged.links = llm.links.isEmpty ? heuristic.links : llm.links
        merged.summary = llm.summary ?? heuristic.summary
        merged.skills = llm.skills.isEmpty ? heuristic.skills : llm.skills
        merged.skillGroups = llm.skillGroups.isEmpty ? heuristic.skillGroups : llm.skillGroups
        if merged.skills.isEmpty, !merged.skillGroups.isEmpty {
            merged.skills = Array(merged.skillGroups.flatMap(\.skills).prefix(60))
        }
        merged.certifications = llm.certifications.isEmpty ? heuristic.certifications : llm.certifications
        merged.otherSections = heuristic.otherSections

        merged.experience = mergeStructuredEntries(llm: llm.experience, heuristic: heuristic.experience)
        merged.projects = mergeStructuredEntries(llm: llm.projects, heuristic: heuristic.projects)
        merged.education = mergeStructuredEntries(llm: llm.education, heuristic: heuristic.education)

        return merged
    }

    private static func mergeStructuredEntries(
        llm: [CareerResumeStructuredProfile.Entry],
        heuristic: [CareerResumeStructuredProfile.Entry]
    ) -> [CareerResumeStructuredProfile.Entry] {
        let llmScore = structureScore(llm)
        let heuristicScore = structureScore(heuristic)

        if llm.isEmpty { return heuristic }
        if heuristic.isEmpty { return llm }

        if llmScore >= heuristicScore {
            return unionEntries(primary: llm, secondary: heuristic)
        }
        return unionEntries(primary: heuristic, secondary: llm)
    }

    private static func unionEntries(
        primary: [CareerResumeStructuredProfile.Entry],
        secondary: [CareerResumeStructuredProfile.Entry]
    ) -> [CareerResumeStructuredProfile.Entry] {
        var merged = primary

        for candidate in secondary {
            if let index = merged.firstIndex(where: { entriesMatch($0, candidate) }) {
                merged[index].bullets = unionBullets(merged[index].bullets, candidate.bullets)
                if merged[index].headingLines.isEmpty {
                    merged[index].headingLines = candidate.headingLines
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged
    }

    private static func unionBullets(_ primary: [String], _ secondary: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for bullet in primary + secondary {
            let trimmed = bullet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func entriesMatch(
        _ lhs: CareerResumeStructuredProfile.Entry,
        _ rhs: CareerResumeStructuredProfile.Entry
    ) -> Bool {
        let left = normalizedEntryTitle(lhs)
        let right = normalizedEntryTitle(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        if left.contains(right) || right.contains(left) { return true }

        let leftTokens = Set(left.split(separator: " ").filter { $0.count >= 4 })
        let rightTokens = Set(right.split(separator: " ").filter { $0.count >= 4 })
        let overlap = leftTokens.intersection(rightTokens).count
        return overlap >= 2
    }

    private static func normalizedEntryTitle(_ entry: CareerResumeStructuredProfile.Entry) -> String {
        let raw = entry.headingLines.first ?? entry.bullets.first ?? ""
        return raw.lowercased()
            .replacingOccurrences(
                of: #"(?i)\b(fall|spring|summer|winter|january|february|march|april|may|june|july|august|september|october|november|december)\s+20\d{2}\b"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .components(separatedBy: .whitespaces)
            .filter { $0.count >= 3 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func structureScore(_ entries: [CareerResumeStructuredProfile.Entry]) -> Int {
        entries.reduce(0) { partial, entry in
            let validBullets = entry.bullets.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            var score = entry.headingLines.count * 2 + validBullets * 3
            if entryHasDateLikeCompany(entry) { score -= 25 }
            if validBullets == 0, entry.headingLines.count > 2 { score -= 10 }
            return partial + max(0, score)
        }
    }

    private static func entryHasDateLikeCompany(_ entry: CareerResumeStructuredProfile.Entry) -> Bool {
        guard entry.headingLines.count >= 2 else { return false }
        let second = entry.headingLines[1]
        if CareerResumeDateParser.parseDateRange(from: second) != nil { return true }
        return second.range(
            of: #"(?i)^(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}$"#,
            options: .regularExpression
        ) != nil
    }
}
