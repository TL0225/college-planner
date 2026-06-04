// RequirementRowNormalizer.swift
// Feature: Catalog
// Purpose: Catalog module — DisplayHierarchy.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Canonical emission of `DegreeRequirement` rows from CourseLeaf and Modern Campus parsers.
enum RequirementRowNormalizer {

    static let categorySeparator = " — "

    static func splitCategoryPath(_ category: String) -> (parent: String?, title: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, "") }
        if let range = trimmed.range(of: categorySeparator, options: .backwards) {
            let parent = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (parent.isEmpty ? nil : parent, title.isEmpty ? trimmed : title)
        }
        return (nil, trimmed)
    }

    static func categoryPath(parent: String, title: String) -> String {
        let p = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return t }
        guard !t.isEmpty else { return p }
        return "\(p)\(categorySeparator)\(t)"
    }

    /// UI hierarchy for Requirements Breakdown: one section header, leaf row title on the category line.
    struct DisplayHierarchy: Sendable, Equatable {
        let sectionHeader: String?
        let rowTitle: String
    }

    static func displayHierarchy(
        categoryPath: String,
        displayTitle: String?,
        rowKind: RequirementKind?
    ) -> DisplayHierarchy {
        let parts = categoryPath
            .components(separatedBy: categorySeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let leafFromDisplay = (displayTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pathLeaf = parts.last ?? categoryPath
        let leaf = leafFromDisplay.isEmpty ? pathLeaf : leafFromDisplay

        guard parts.count >= 2 else {
            return DisplayHierarchy(
                sectionHeader: parts.first,
                rowTitle: leaf
            )
        }

        return DisplayHierarchy(
            sectionHeader: parts[0],
            rowTitle: leaf
        )
    }

    static func inferKind(
        required: [CourseDetail],
        selectFrom: [CourseDetail],
        selectCount: Int?,
        creditsRequired: Int,
        description: String?,
        explicitKind: RequirementKind? = nil
    ) -> RequirementKind {
        if let explicitKind { return explicitKind }
        if !selectFrom.isEmpty, (selectCount ?? 0) > 0 { return .chooseOne }
        if !required.isEmpty { return .courseList }
        let proseCredits = RequirementBreakdownCredits.creditsMentionedInProse(description ?? "")
        let hasCredits = creditsRequired > 0 || proseCredits > 0
        if hasCredits {
            let lower = (description ?? "").lowercased()
            let parentLower = lower
            if lower.contains("elective") || lower.contains("choose ") || lower.contains("select ")
                || lower.contains("complete ") || lower.contains("4xx") || lower.contains("700") {
                return .ruleBucket
            }
            if parentLower.contains("general education") || parentLower.contains("distribution")
                || parentLower.contains("foreign language") || parentLower.contains("physical science")
                || parentLower.contains("life science") || parentLower.contains("humanities") {
                return .distributionBucket
            }
            return .ruleBucket
        }
        if !(description?.isEmpty ?? true) { return .prose }
        return .courseList
    }

    static func makeRequirement(
        degreeType: String = "Unknown",
        major: String = "Unknown",
        parentCategory: String,
        displayTitle: String,
        kind: RequirementKind,
        required: [CourseDetail] = [],
        selectFrom: [CourseDetail] = [],
        creditsRequired: Int = 0,
        description: String? = nil,
        selectCount: Int? = nil,
        requirementPredicate: RequirementPredicate? = nil
    ) -> DegreeRequirement {
        let category = categoryPath(parent: parentCategory, title: displayTitle)
        let requiredUnique = Array(Set(required)).sorted { $0.code < $1.code }
        let selectUnique = Array(Set(selectFrom)).sorted { $0.code < $1.code }
        let proseCredits = RequirementBreakdownCredits.creditsMentionedInProse(description ?? "")
        let effectiveCredits = max(creditsRequired, proseCredits)

        return DegreeRequirement(
            degreeType: degreeType,
            major: major,
            category: category,
            requiredCourses: requiredUnique.isEmpty ? nil : requiredUnique.map(\.code),
            requiredCoursesDetailed: requiredUnique.isEmpty ? nil : requiredUnique,
            creditsRequired: effectiveCredits,
            description: description,
            selectFrom: selectUnique.isEmpty ? nil : selectUnique.map(\.code),
            selectFromDetailed: selectUnique.isEmpty ? nil : selectUnique,
            selectCount: {
                if !selectUnique.isEmpty { return selectCount ?? 1 }
                if let selectCount, selectCount > 0,
                   kind == .chooseOne || kind == .ruleBucket {
                    return selectCount
                }
                return nil
            }(),
            requirementPredicate: requirementPredicate,
            requirementKind: kind,
            parentCategory: parentCategory,
            displayTitle: displayTitle
        )
    }

    static func applySemantics(to requirement: DegreeRequirement) -> DegreeRequirement {
        let required = requirement.requiredCoursesDetailed ?? []
        let selectFrom = requirement.selectFromDetailed ?? []
        let inferred = inferKind(
            required: required,
            selectFrom: selectFrom,
            selectCount: requirement.selectCount,
            creditsRequired: requirement.creditsRequired,
            description: requirement.description,
            explicitKind: requirement.requirementKind
        )
        let split = splitCategoryPath(requirement.category)
        let parent = requirement.parentCategory ?? split.parent ?? split.title
        let title = requirement.displayTitle ?? (split.parent == nil ? split.title : split.title)

        return DegreeRequirement(
            id: requirement.id,
            degreeType: requirement.degreeType,
            major: requirement.major,
            category: requirement.category,
            requiredCourses: requirement.requiredCourses,
            requiredCoursesDetailed: requirement.requiredCoursesDetailed,
            creditsRequired: requirement.creditsRequired,
            description: requirement.description,
            selectFrom: requirement.selectFrom,
            selectFromDetailed: requirement.selectFromDetailed,
            selectCount: requirement.selectCount,
            requirementPredicate: requirement.requirementPredicate,
            requirementKind: inferred,
            parentCategory: parent,
            displayTitle: title.isEmpty ? nil : title
        )
    }
}
