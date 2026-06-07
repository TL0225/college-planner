// CatalogSanityConstraints.swift
// Feature: Catalog
// Purpose: Cheap post-extraction sanity checks against historical baselines.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogSanityConstraints {
    struct Result: Sendable, Equatable {
        let passed: Bool
        let severity: CatalogReviewSeverity
        let messages: [String]
    }

    private static let programDropFactor = 0.5
    private static let programSpikeFactor = 3.0
    private static let maxRequirementTablesPerProgram = 50

    static func evaluate(
        metrics: CatalogExtractorMetrics,
        expectCourses: Bool,
        expectPrograms: Bool
    ) -> Result {
        var messages: [String] = []
        var critical = false

        if expectPrograms, metrics.programsFound == 0 {
            messages.append("No programs found.")
            critical = true
        }

        if expectCourses, metrics.coursesFound == 0 {
            messages.append("No courses found on full catalog sync.")
            critical = true
        }

        if let baseline = CatalogExtractorMetricsBaselineStore.load(
            schoolID: metrics.schoolID,
            catalogVersionID: metrics.catalogVersionID
        ) {
            if baseline.programsFound > 0,
               Double(metrics.programsFound) < Double(baseline.programsFound) * programDropFactor {
                messages.append(
                    "Program count \(metrics.programsFound) is below 50% of baseline \(baseline.programsFound)."
                )
                critical = true
            }
            if baseline.programsFound > 0,
               Double(metrics.programsFound) > Double(baseline.programsFound) * programSpikeFactor {
                messages.append(
                    "Program count \(metrics.programsFound) exceeds 3× baseline \(baseline.programsFound)."
                )
                critical = true
            }
        }

        if metrics.programsFound > 0,
           metrics.requirementTablesFound > metrics.programsFound * maxRequirementTablesPerProgram {
            messages.append("Requirement table count looks runaway vs program count.")
            critical = true
        }

        let severity: CatalogReviewSeverity = critical ? .critical : (messages.isEmpty ? .informational : .warning)
        return Result(passed: !critical, severity: severity, messages: messages)
    }
}
