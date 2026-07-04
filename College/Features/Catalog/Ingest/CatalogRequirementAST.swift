// CatalogRequirementAST.swift
// Feature: Catalog
// Purpose: Bridge flat DegreeRequirement rows to RequirementPredicate AST (P21).

import Foundation

enum CatalogRequirementAST {
    static func encode(_ predicate: RequirementPredicate?) -> String? {
        guard let predicate,
              let data = try? JSONEncoder().encode(predicate) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> RequirementPredicate? {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RequirementPredicate.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func build(from requirement: DegreeRequirement, courses: [CourseDetail]) -> RequirementPredicate? {
        if let existing = requirement.requirementPredicate {
            return existing
        }
        let required = courses.map { RequirementPredicate.course($0) }
        guard !required.isEmpty else { return nil }
        if let selectCount = requirement.selectCount, selectCount > 1 {
            return .any(required, selectCount: selectCount)
        }
        if required.count == 1 {
            return required[0]
        }
        return .all(required)
    }

    static func attachAST(to requirements: [DegreeRequirement]) -> [DegreeRequirement] {
        requirements.map { row in
            guard row.requirementPredicate == nil,
                  let courses = row.requiredCoursesDetailed, !courses.isEmpty,
                  let ast = build(from: row, courses: courses) else {
                return row
            }
            return DegreeRequirement(
                id: row.id,
                degreeType: row.degreeType,
                major: row.major,
                category: row.category,
                requiredCourses: row.requiredCourses,
                requiredCoursesDetailed: row.requiredCoursesDetailed,
                creditsRequired: row.creditsRequired,
                description: row.description,
                selectFrom: row.selectFrom,
                selectFromDetailed: row.selectFromDetailed,
                selectCount: row.selectCount,
                requirementPredicate: ast,
                requirementKind: row.requirementKind,
                parentCategory: row.parentCategory,
                displayTitle: row.displayTitle
            )
        }
    }
}
