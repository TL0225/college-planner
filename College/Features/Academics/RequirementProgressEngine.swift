// RequirementProgressEngine.swift
// Feature: Academics
// Purpose: Academics module — RequirementCourseSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct RequirementCourseSnapshot: Sendable, Equatable {
    let code: String
    let credits: Int
    let isCompleted: Bool
    let isElective: Bool
}

struct RequirementSectionSnapshot: Sendable, Equatable {
    let categoryKey: String
    let requirementKind: RequirementKind
    let selectCount: Int
    let creditsRequired: Int
    let descriptionCredits: Int
    let requiredItems: [RequirementCourseSnapshot]
    let electiveItems: [RequirementCourseSnapshot]
    let assignedItems: [RequirementCourseSnapshot]
}

struct RequirementCompletionInfo: Sendable, Equatable {
    let isCompleted: Bool
    let credits: Int
}

enum RequirementProgressEngine {

    static func target(for section: RequirementSectionSnapshot) -> Int {
        switch section.requirementKind {
        case .distributionBucket, .ruleBucket:
            return max(section.creditsRequired, section.descriptionCredits)
        case .chooseOne:
            if section.creditsRequired > 0 { return section.creditsRequired }
            if section.descriptionCredits > 0 { return section.descriptionCredits }
            fallthrough
        default:
            return RequirementBreakdownCredits.progressTarget(
                items: auditItems(from: section),
                selectCount: section.selectCount,
                descriptionCredits: section.descriptionCredits
            )
        }
    }

    static func completed(for section: RequirementSectionSnapshot) -> Int {
        switch section.requirementKind {
        case .distributionBucket, .ruleBucket:
            let cap = target(for: section)
            let assigned = section.assignedItems.filter(\.isCompleted).map(\.credits).reduce(0, +)
            let listedCompleted = section.requiredItems.filter(\.isCompleted).map(\.credits).reduce(0, +)
            let electiveCompleted = section.electiveItems.filter(\.isCompleted).map(\.credits).reduce(0, +)
            return min(cap, assigned + listedCompleted + electiveCompleted)
        case .chooseOne:
            return RequirementBreakdownCredits.sumCompletedCredits(
                items: auditItems(from: section),
                selectCount: max(section.selectCount, 1),
                descriptionCredits: section.descriptionCredits,
                headerCredits: section.creditsRequired
            )
        default:
            return RequirementBreakdownCredits.sumCompletedCredits(
                items: auditItems(from: section),
                selectCount: section.selectCount,
                descriptionCredits: section.descriptionCredits,
                headerCredits: section.creditsRequired
            )
        }
    }

    static func isDone(for section: RequirementSectionSnapshot) -> Bool {
        let t = target(for: section)
        guard t > 0 else { return false }
        return completed(for: section) >= t
    }

    static func claimedCodes(sections: [RequirementSectionSnapshot]) -> Set<String> {
        var codes = Set<String>()
        for section in sections {
            for item in section.requiredItems + section.electiveItems + section.assignedItems {
                let code = item.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !code.isEmpty else { continue }
                codes.insert(code)
            }
        }
        return codes
    }

    static func buildSnapshot(
        from requirement: CatalogDegreeRequirement,
        fulfillments: [RequirementFulfillment],
        completionByCode: [String: RequirementCompletionInfo]
    ) -> RequirementSectionSnapshot {
        let categoryKey = requirement.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = RequirementKind(rawValue: requirement.requirementKind ?? "") ?? inferredKind(from: requirement)
        let selectCount = Int(requirement.selectCount)
        let storedCredits = Int(requirement.creditsRequired)
        let description = requirement.descriptionText ?? ""
        let descriptionCredits = RequirementBreakdownCredits.creditsMentionedInProse(description)
        let effectiveDescriptionCredits = max(descriptionCredits, storedCredits > 0 && kind == .chooseOne ? storedCredits : descriptionCredits)

        let requiredItems = courseSnapshots(
            fromDetailedJSON: requirement.requiredCoursesDetailedJSON,
            fromCSV: requirement.requiredCourses,
            isElective: false,
            completionByCode: completionByCode
        )
        let electiveItems = courseSnapshots(
            fromDetailedJSON: requirement.selectFromDetailedJSON,
            fromCSVJSON: requirement.selectFromJSON,
            isElective: true,
            completionByCode: completionByCode
        )
        let assignedItems = fulfillments
            .filter { $0.requirementCategory.caseInsensitiveCompare(categoryKey) == .orderedSame }
            .map { fulfillment -> RequirementCourseSnapshot in
                let code = fulfillment.courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let info = completionByCode[code] ?? RequirementCompletionInfo(isCompleted: false, credits: 0)
                return RequirementCourseSnapshot(
                    code: code,
                    credits: info.credits,
                    isCompleted: info.isCompleted,
                    isElective: true
                )
            }

        return RequirementSectionSnapshot(
            categoryKey: categoryKey,
            requirementKind: kind,
            selectCount: selectCount,
            creditsRequired: storedCredits,
            descriptionCredits: effectiveDescriptionCredits,
            requiredItems: requiredItems,
            electiveItems: electiveItems,
            assignedItems: assignedItems
        )
    }

    static func inferredKind(from requirement: CatalogDegreeRequirement) -> RequirementKind {
        let hasRequired = !(requirement.requiredCourses ?? "").isEmpty
            || !(requirement.requiredCoursesDetailedJSON ?? "").isEmpty
        let hasSelect = !(requirement.selectFromJSON ?? "").isEmpty
            || !(requirement.selectFromDetailedJSON ?? "").isEmpty
        let selectCount = Int(requirement.selectCount)
        if hasSelect, selectCount > 0 { return .chooseOne }
        if hasRequired { return .courseList }
        let storedCredits = Int(requirement.creditsRequired)
        let descriptionCredits = RequirementBreakdownCredits.creditsMentionedInProse(requirement.descriptionText ?? "")
        if storedCredits > 0 || descriptionCredits > 0 {
            let lower = requirement.requirementCategory.lowercased()
            if lower.contains("elective") || lower.contains("4xx") { return .ruleBucket }
            if lower.contains("general education") || lower.contains("foreign language")
                || lower.contains("physical science") || lower.contains("life science") {
                return .distributionBucket
            }
            return .ruleBucket
        }
        return .prose
    }

    private static func auditItems(from section: RequirementSectionSnapshot) -> [AcademicsAuditPanel.AuditItem] {
        var items: [AcademicsAuditPanel.AuditItem] = []
        for snapshot in section.requiredItems {
            items.append(
                AcademicsAuditPanel.AuditItem(
                    code: snapshot.code,
                    credits: snapshot.credits > 0 ? "\(snapshot.credits)" : "",
                    title: "",
                    grade: nil,
                    planProgress: snapshot.isCompleted ? .completed : .notOnPlan,
                    isElective: false
                )
            )
        }
        for snapshot in section.electiveItems + section.assignedItems {
            items.append(
                AcademicsAuditPanel.AuditItem(
                    code: snapshot.code,
                    credits: snapshot.credits > 0 ? "\(snapshot.credits)" : "",
                    title: "",
                    grade: nil,
                    planProgress: snapshot.isCompleted ? .completed : .notOnPlan,
                    isElective: true
                )
            )
        }
        return items
    }

    private static func courseSnapshots(
        fromDetailedJSON json: String?,
        fromCSV csv: String? = nil,
        fromCSVJSON csvJSON: String? = nil,
        isElective: Bool,
        completionByCode: [String: RequirementCompletionInfo]
    ) -> [RequirementCourseSnapshot] {
        var snapshots: [RequirementCourseSnapshot] = []
        if let json, let data = json.data(using: .utf8),
           let detailed = try? JSONDecoder().decode([CourseDetail].self, from: data) {
            for detail in detailed {
                let code = detail.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !code.isEmpty else { continue }
                let info = completionByCode[code] ?? RequirementCompletionInfo(isCompleted: false, credits: 0)
                let credits = info.credits > 0 ? info.credits : RequirementBreakdownCredits.creditValue(from: detail.credits ?? "")
                snapshots.append(
                    RequirementCourseSnapshot(code: code, credits: credits, isCompleted: info.isCompleted, isElective: isElective)
                )
            }
            return snapshots
        }
        let codes: [String]
        if let csvJSON, let data = csvJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            codes = decoded
        } else if let csv {
            codes = csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            codes = []
        }
        for raw in codes {
            let code = raw.uppercased()
            guard !code.isEmpty else { continue }
            let info = completionByCode[code] ?? RequirementCompletionInfo(isCompleted: false, credits: 0)
            snapshots.append(
                RequirementCourseSnapshot(code: code, credits: info.credits, isCompleted: info.isCompleted, isElective: isElective)
            )
        }
        return snapshots
    }
}
