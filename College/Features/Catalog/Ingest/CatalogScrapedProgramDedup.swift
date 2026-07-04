// CatalogScrapedProgramDedup.swift
// Feature: Catalog
// Purpose: Collapse duplicate scraped program rows before ingest gate / persistence.

import Foundation

enum CatalogScrapedProgramDedup {
    /// Collapse rows that share the same catalog edition and canonical program name.
    /// Keeps the most specific row (typed degree suffix, department, longer name).
    static func collapseByCanonicalMajor(
        _ programsByKey: [String: ScrapedProgram]
    ) -> [String: ScrapedProgram] {
        var buckets: [String: [(key: String, program: ScrapedProgram)]] = [:]
        var order: [String] = []

        for (key, program) in programsByKey {
            let bucket = bucketKey(for: key, program: program)
            if buckets[bucket] == nil {
                order.append(bucket)
                buckets[bucket] = []
            }
            buckets[bucket]?.append((key: key, program: program))
        }

        var collapsed: [String: ScrapedProgram] = [:]
        collapsed.reserveCapacity(buckets.count)
        for bucket in order {
            guard let group = buckets[bucket], let best = group.max(by: { specificityScore($0.program) < specificityScore($1.program) }) else {
                continue
            }
            collapsed[best.key] = best.program
        }
        return collapsed
    }

    private static func bucketKey(for dedupKey: String, program: ScrapedProgram) -> String {
        let catoid = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
        let canonical = canonicalProgramStem(program)
        let minorFlag = program.type.lowercased().contains("minor") ? "m" : "p"
        return "\(catoid)|\(canonical)|\(minorFlag)"
    }

    private static func canonicalProgramStem(_ program: ScrapedProgram) -> String {
        let trimmed = program.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = CatalogDegreeTypeFilter.suffixToken(fromDisplayName: trimmed) {
            let stem = trimmed
                .replacingOccurrences(of: ", \(suffix)", with: "")
                .replacingOccurrences(of: " \(suffix)", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stem.isEmpty { return stem.lowercased() }
        }
        return trimmed.lowercased()
    }

    private static func specificityScore(_ program: ScrapedProgram) -> Int {
        var score = 0
        if let degree = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !degree.isEmpty {
            score += 4
        }
        if program.name.contains(",") { score += 2 }
        if let department = program.department?.trimmingCharacters(in: .whitespacesAndNewlines), !department.isEmpty {
            score += 2
        }
        score += min(3, program.name.count / 20)
        if program.url.lowercased().contains("preview_program") { score += 1 }
        return score
    }
}
