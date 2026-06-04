// GraduationTimelinePrereqValidator.swift
// Feature: Academics
// Purpose: Academics module — Warning.
// Data: CollegePersistence / repositories when applicable.

// GraduationTimelinePrereqValidator.swift
// Walks planner courses and flags rows whose catalog prerequisite rules aren't satisfied
// by an earlier term in the same plan.

import Foundation

enum GraduationTimelinePrereqValidator {

    struct Warning: Identifiable, Equatable {
        let id: UUID
        let courseCode: String
        let termLabel: String
        let missingCourses: [String]
        let message: String
    }

    struct ScheduledCourse {
        let code: String
        let year: Int
        let season: String
        let isCompleted: Bool
    }

    static func validate(
        scheduledCourses: [ScheduledCourse],
        catalogLookup: (String) -> CourseCatalog?
    ) -> [Warning] {
        guard !scheduledCourses.isEmpty else { return [] }

        let ordered = scheduledCourses.map { sc in
            (sc, termOrderKey(year: sc.year, season: sc.season))
        }

        var earliestSatisfied: [String: Double] = [:]
        for (sc, order) in ordered {
            let key = normalize(sc.code)
            guard !key.isEmpty else { continue }
            if let existing = earliestSatisfied[key] {
                earliestSatisfied[key] = min(existing, order)
            } else {
                earliestSatisfied[key] = order
            }
        }

        var warnings: [Warning] = []
        for (sc, scheduledOrder) in ordered {
            guard let catalog = catalogLookup(sc.code) else { continue }
            guard let rulesJSON = catalog.prerequisiteRulesJSON,
                  let data = rulesJSON.data(using: .utf8),
                  let rule = try? JSONDecoder().decode(PrerequisiteRule.self, from: data)
            else { continue }

            let missing = evaluate(
                rule: rule,
                schedulingOrder: scheduledOrder,
                earliestSatisfied: earliestSatisfied
            )
            guard !missing.isEmpty else { continue }
            let label = "\(sc.season) \(sc.year)"
            let message = "Move/add \(missing.joined(separator: ", ")) before \(sc.code) (\(label))"
            warnings.append(
                Warning(
                    id: UUID(),
                    courseCode: sc.code,
                    termLabel: label,
                    missingCourses: missing,
                    message: message
                )
            )
        }
        return warnings
    }

    private static func evaluate(
        rule: PrerequisiteRule,
        schedulingOrder: Double,
        earliestSatisfied: [String: Double]
    ) -> [String] {
        switch rule {
        case .course(let req):
            let code = normalize(req.courseCode)
            if let satisfiedAt = earliestSatisfied[code], satisfiedAt < schedulingOrder {
                return []
            }
            return [req.courseCode]

        case .and(let rules):
            var missing: [String] = []
            for r in rules {
                missing.append(contentsOf: evaluate(
                    rule: r,
                    schedulingOrder: schedulingOrder,
                    earliestSatisfied: earliestSatisfied
                ))
            }
            return missing

        case .or(let rules):
            var perOption: [[String]] = []
            for r in rules {
                let m = evaluate(
                    rule: r,
                    schedulingOrder: schedulingOrder,
                    earliestSatisfied: earliestSatisfied
                )
                if m.isEmpty { return [] }
                perOption.append(m)
            }
            return perOption.min(by: { $0.count < $1.count }) ?? []
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func termOrderKey(year: Int, season: String) -> Double {
        let order = seasonSortOrder(season)
        return Double(year) + Double(order) * 0.1
    }

    private static func seasonSortOrder(_ season: String) -> Int {
        switch season.lowercased() {
        case "spring": return 0
        case "summer": return 1
        case "fall": return 2
        case "winter": return 3
        default: return 0
        }
    }
}
