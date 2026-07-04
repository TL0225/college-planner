// CatalogAuditReadinessScorer.swift
// Feature: Catalog
// Purpose: Degree audit readiness scoring per program (P27).

import Foundation

struct CatalogAuditReadinessReport: Sendable, Equatable {
    let programName: String
    let score: Double
    let hasCourses: Bool
    let hasRequirements: Bool
    let hasTracks: Bool
    let hasCreditLogic: Bool
    let hasPrerequisites: Bool
    let gaps: [String]
}

enum CatalogAuditReadinessScorer {
    static func scoreProgram(
        name: String,
        requirements: [DegreeRequirement],
        courses: [CatalogCourse],
        tracks: [String] = []
    ) -> CatalogAuditReadinessReport {
        let programReqs = requirements.filter {
            $0.major.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        let hasRequirements = !programReqs.isEmpty
        let hasCourses = !courses.isEmpty
        let hasTracks = !tracks.isEmpty
        let hasCreditLogic = programReqs.contains { $0.creditsRequired > 0 }
        let hasPrerequisites = courses.contains {
            ($0.prerequisiteText?.isEmpty == false) || $0.prerequisites != nil
        }

        var gaps: [String] = []
        if !hasRequirements { gaps.append("requirements") }
        if !hasCourses { gaps.append("courses") }
        if !hasCreditLogic { gaps.append("credit_logic") }
        if !hasPrerequisites { gaps.append("prerequisites") }

        let components: [Double] = [
            hasRequirements ? 0.30 : 0,
            hasCourses ? 0.25 : 0,
            hasCreditLogic ? 0.20 : 0,
            hasPrerequisites ? 0.15 : 0,
            hasTracks ? 0.10 : 0.05,
        ]
        let score = components.reduce(0, +)

        return CatalogAuditReadinessReport(
            programName: name,
            score: score,
            hasCourses: hasCourses,
            hasRequirements: hasRequirements,
            hasTracks: hasTracks,
            hasCreditLogic: hasCreditLogic,
            hasPrerequisites: hasPrerequisites,
            gaps: gaps
        )
    }

    static func averageScore(for programs: [String], requirements: [DegreeRequirement], courses: [CatalogCourse]) -> Double {
        guard !programs.isEmpty else { return 0 }
        let scores = programs.map { scoreProgram(name: $0, requirements: requirements, courses: courses).score }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
