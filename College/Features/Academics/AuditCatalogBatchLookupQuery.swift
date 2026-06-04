// AuditCatalogBatchLookupQuery.swift
// Feature: Academics
// Purpose: Academics module — AuditCatalogBatchLookupQuery.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Background-safe catalog course batch match for Academics audit (Phase 3 P0).
enum AuditCatalogBatchLookupQuery {
    static func matchingBatch(
        universityID: UUID,
        codes rawCodes: [String],
        context: ModelContext
    ) throws -> [String: CourseCatalog] {
        var keyToCandidates: [String: [String]] = [:]
        for raw in rawCodes {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty else { continue }
            if keyToCandidates[key] == nil {
                keyToCandidates[key] = CatalogImportTransforms.catalogLookupCandidates(for: raw)
            }
        }
        guard !keyToCandidates.isEmpty else { return [:] }

        let candidateSet = Set(keyToCandidates.values.flatMap { $0 })
        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: #Predicate { course in
                course.university?.id == universityID
            }
        )
        descriptor.fetchLimit = 50_000
        let courses = try context.fetch(descriptor)

        var courseByStoredCode: [String: CourseCatalog] = [:]
        for course in courses {
            let stored = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidateSet.contains(stored) || candidateSet.contains(stored.uppercased()) else { continue }
            if let existing = courseByStoredCode[stored],
               qualityScore(course) <= qualityScore(existing) {
                continue
            }
            courseByStoredCode[stored] = course
            let upper = stored.uppercased()
            if upper != stored {
                courseByStoredCode[upper] = course
            }
        }

        var result: [String: CourseCatalog] = [:]
        for (key, candidates) in keyToCandidates {
            for candidate in candidates {
                let hit = courseByStoredCode[candidate] ?? courseByStoredCode[candidate.uppercased()]
                guard let hit else { continue }
                if let existing = result[key], qualityScore(hit) <= qualityScore(existing) {
                    continue
                }
                result[key] = hit
                break
            }
        }
        return result
    }

    private static func qualityScore(_ course: CourseCatalog) -> Int {
        let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0
        if course.credits > 0 { score += 3 }
        if !title.isEmpty && title.uppercased() != code.uppercased() { score += 2 }
        if let desc = course.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        return score
    }
}
