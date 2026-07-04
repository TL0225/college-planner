// CatalogSemanticConstraintValidator.swift
// Feature: Catalog
// Purpose: Semantic consistency checks beyond count-based sanity.

import Foundation

enum CatalogSemanticConstraintValidator {
    struct Result: Sendable, Equatable {
        let passed: Bool
        let severity: CatalogReviewSeverity
        let messages: [String]
    }

    static func evaluate(
        programs: [ScrapedProgram],
        courses: [CatalogCourse],
        requirements: [DegreeRequirement],
        expectRequirements: Bool
    ) -> Result {
        var messages: [String] = []
        var critical = false

        // 1) Course-reference existence checks.
        let knownCourseCodes = Set(
            courses.map { normalizeCode($0.courseCode) }.filter { !$0.isEmpty }
        )
        if !knownCourseCodes.isEmpty {
            let referencedCodes = requirementCodes(requirements)
            let dangling = referencedCodes.filter { !knownCourseCodes.contains($0) }
            if !referencedCodes.isEmpty {
                let danglingRatio = Double(dangling.count) / Double(referencedCodes.count)
                if danglingRatio > 0.15 {
                    messages.append(
                        String(
                            format: "Requirement references missing courses (%.1f%% dangling: %d/%d).",
                            danglingRatio * 100,
                            dangling.count,
                            referencedCodes.count
                        )
                    )
                    critical = true
                } else if !dangling.isEmpty {
                    messages.append("Some requirement course references are unresolved (\(dangling.count)).")
                }
            }
        }

        // 2) Program credit-total plausibility (sum of group credits by major).
        // Guard against impossible low totals that usually indicate parsing collapse.
        let creditsByMajor = Dictionary(grouping: requirements, by: { normalizedName($0.major) })
            .mapValues { rows in rows.reduce(0) { $0 + max(0, $1.creditsRequired) } }
        for (major, totalCredits) in creditsByMajor where !major.isEmpty {
            if totalCredits > 0 && totalCredits < 12 {
                messages.append("Requirement credits look implausibly low for \(major) (\(totalCredits) total).")
            }
        }

        // 3) Program ownership checks: requirements should map back to known programs.
        let knownPrograms = Set(programs.map { normalizedName($0.name) }.filter { !$0.isEmpty })
        if expectRequirements, !knownPrograms.isEmpty {
            let reqMajors = Set(requirements.map { normalizedName($0.major) }.filter { !$0.isEmpty })
            let orphanMajors = reqMajors.subtracting(knownPrograms)
            if !orphanMajors.isEmpty {
                messages.append("Requirement groups found for unknown programs (\(orphanMajors.count)).")
                critical = true
            }
        }

        let severity: CatalogReviewSeverity = critical ? .critical : (messages.isEmpty ? .informational : .warning)
        return Result(passed: !critical, severity: severity, messages: messages)
    }

    private static func requirementCodes(_ requirements: [DegreeRequirement]) -> Set<String> {
        var codes = Set<String>()
        for req in requirements {
            for code in req.requiredCourses ?? [] {
                let normalized = normalizeCode(code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
            for code in req.selectFrom ?? [] {
                let normalized = normalizeCode(code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
            for detail in req.requiredCoursesDetailed ?? [] {
                let normalized = normalizeCode(detail.code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
            for detail in req.selectFromDetailed ?? [] {
                let normalized = normalizeCode(detail.code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
        }
        return codes
    }

    private static func normalizeCode(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
