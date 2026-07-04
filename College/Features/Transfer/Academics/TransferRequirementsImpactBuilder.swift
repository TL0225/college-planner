// TransferRequirementsImpactBuilder.swift
// Feature: Transfer / Academics
// Purpose: Transfer Database — projects transfer results onto degree requirements.
// Data: Pure value transforms over bridge outputs.

import Foundation

/// Builds the "how does this transfer affect my degree" table from requirement targets,
/// the learner's plan courses, and scored transfer results.
enum TransferRequirementsImpactBuilder {
    static func build(
        requirements: [TransferRequirementTarget],
        planCourses: [TransferPlanCourse],
        results: [TransferCourseResult]
    ) -> [TransferRequirementsImpactRow] {
        let planByCode = Dictionary(
            planCourses.map { ($0.normalizedCode, $0) },
            uniquingKeysWith: { lhs, rhs in
                // Prefer the most-progressed bucket if a course appears more than once.
                bucketPriority(lhs.bucket) >= bucketPriority(rhs.bucket) ? lhs : rhs
            }
        )

        var rows: [TransferRequirementsImpactRow] = []
        for requirement in requirements {
            for targetCode in requirement.courseCodes {
                let normalizedTarget = CatalogImportTransforms.normalizeCourseCode(targetCode)
                guard !normalizedTarget.isEmpty else { continue }

                let candidates = TransferCourseMatcher.results(
                    matchingTargetCourseCode: normalizedTarget,
                    in: results
                )
                guard let best = candidates.max(by: { $0.confidence < $1.confidence }) else { continue }

                let matchedSourcePlan = planByCode[CatalogImportTransforms.normalizeCourseCode(best.sourceCourseCode)]
                let targetAlreadyCompleted = planByCode[normalizedTarget]?.bucket == .completed
                let satisfied = targetAlreadyCompleted || matchedSourcePlan?.bucket == .completed

                let bucket: TransferCourseScheduleBucket = {
                    if targetAlreadyCompleted { return .completed }
                    return matchedSourcePlan?.bucket ?? .unscheduled
                }()

                let credits = best.targetCredits > 0
                    ? best.targetCredits
                    : (matchedSourcePlan?.credits ?? 0)

                rows.append(
                    TransferRequirementsImpactRow(
                        requirementCategory: requirement.category,
                        requirementDisplayTitle: requirement.displayTitle,
                        targetCourseCode: best.targetCourseCode,
                        targetCourseTitle: best.targetCourseTitle,
                        matchedSourceCourseCode: matchedSourcePlan?.code ?? best.sourceCourseCode,
                        creditsApplied: credits,
                        bucket: bucket,
                        confidence: best.confidence,
                        alreadySatisfied: satisfied
                    )
                )
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.requirementCategory != rhs.requirementCategory {
                return lhs.requirementCategory < rhs.requirementCategory
            }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.targetCourseCode < rhs.targetCourseCode
        }
    }

    /// Total credits that would be applied across all non-duplicate target courses.
    static func projectedCredits(_ rows: [TransferRequirementsImpactRow]) -> Int {
        var seen = Set<String>()
        var total = 0
        for row in rows {
            let key = CatalogImportTransforms.normalizeCourseCode(row.targetCourseCode)
            guard seen.insert(key).inserted else { continue }
            total += row.creditsApplied
        }
        return total
    }

    private static func bucketPriority(_ bucket: TransferCourseScheduleBucket) -> Int {
        switch bucket {
        case .completed: return 3
        case .inProgress: return 2
        case .planned: return 1
        case .unscheduled: return 0
        }
    }
}
