// CatalogStructuralInvariantValidator.swift
// Feature: Catalog
// Purpose: Pre-persist structural constraints for catalog ingest (highest ROI gate).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogStructuralInvariantValidator {
    struct Input: Sendable {
        let expectPrograms: Bool
        let expectCourses: Bool
        let expectRequirements: Bool
        let programsFound: Int
        let coursesFound: Int
        let requirementsFound: Int
        let orphanRequirementCount: Int
    }

    static func validate(_ input: Input) -> CatalogIngestRecoveryPolicy.InvariantResult {
        var critical: [String] = []
        var warnings: [String] = []
        var failedScopes: [CatalogIngestRecoveryPolicy.IngestScope] = []

        if input.expectPrograms, input.programsFound == 0 {
            critical.append("Invariant: expected programs but found none.")
            failedScopes.append(.programs)
        }

        if input.expectCourses, input.coursesFound == 0 {
            critical.append("Invariant: expected courses but found none.")
            failedScopes.append(.courses)
        }

        if input.expectRequirements, input.requirementsFound == 0, input.programsFound > 0 {
            warnings.append("Invariant: no requirement rows extracted for non-empty program index.")
        }

        if input.orphanRequirementCount > 0 {
            critical.append("Invariant: \(input.orphanRequirementCount) requirement row(s) lack program attachment.")
            failedScopes.append(.requirements)
        }

        let passed = critical.isEmpty
        return CatalogIngestRecoveryPolicy.InvariantResult(
            passed: passed,
            failedScopes: Array(Set(failedScopes)),
            criticalMessages: critical,
            warningMessages: warnings
        )
    }

    /// Count requirements whose major does not match any scraped program name (legacy crawl heuristic).
    static func orphanRequirementCount(
        programs: [ScrapedProgram],
        requirements: [DegreeRequirement]
    ) -> Int {
        let programNames = Set(
            programs.map {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty }
        )
        guard !programNames.isEmpty else { return requirements.isEmpty ? 0 : requirements.count }

        return requirements.filter { req in
            let major = req.major.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !major.isEmpty && !programNames.contains(major)
        }.count
    }
}
