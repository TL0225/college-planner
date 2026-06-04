// CatalogPrerequisiteValidator.swift
// Feature: Catalog
// Purpose: Catalog module — ValidationResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Validates prerequisite rules against the local store course catalog during import.
@MainActor
class CatalogPrerequisiteValidator {

    private let repository: CatalogRepository
    private let universityID: UUID

    private static let deptPrefixRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,4})"#)

    init(repository: CatalogRepository, universityID: UUID) {
        self.repository = repository
        self.universityID = universityID
    }

    struct ValidationResult {
        let isValid: Bool
        let invalidCourseCodes: [String]
        let warnings: [String]
        let confidence: ValidationConfidence

        var needsManualReview: Bool {
            confidence == .invalid || confidence == .needsReview
        }
    }

    enum ValidationConfidence {
        case valid
        case partiallyValid
        case invalid
        case needsReview
    }

    func validate(
        rule: PrerequisiteRule,
        forUniversity universityName: String,
        courseCode: String
    ) -> ValidationResult {
        _ = universityName
        var invalidCodes: [String] = []
        var warnings: [String] = []

        let referencedCodes = extractCourseCodes(from: rule)

        for code in referencedCodes {
            if !courseExists(code: code) {
                invalidCodes.append(code)
                warnings.append("Course \(code) not found in catalog")
            }
        }

        if referencedCodes.contains(courseCode) {
            warnings.append("Circular prerequisite: \(courseCode) requires itself")
        }

        if referencedCodes.isEmpty {
            return ValidationResult(
                isValid: false,
                invalidCourseCodes: [],
                warnings: ["No course codes found in prerequisite rule"],
                confidence: .needsReview
            )
        }

        let confidence: ValidationConfidence
        if invalidCodes.isEmpty && warnings.isEmpty {
            confidence = .valid
        } else if invalidCodes.count <= 1 && referencedCodes.count > 2 {
            confidence = .partiallyValid
        } else if !invalidCodes.isEmpty {
            confidence = .invalid
        } else {
            confidence = .needsReview
        }

        return ValidationResult(
            isValid: invalidCodes.isEmpty,
            invalidCourseCodes: invalidCodes,
            warnings: warnings,
            confidence: confidence
        )
    }

    private func extractCourseCodes(from rule: PrerequisiteRule) -> [String] {
        var codes: [String] = []

        func traverse(_ rule: PrerequisiteRule) {
            switch rule {
            case .course(let req):
                codes.append(req.courseCode)
            case .and(let rules), .or(let rules):
                for subRule in rules {
                    traverse(subRule)
                }
            }
        }

        traverse(rule)
        return codes
    }

    private func courseExists(code: String) -> Bool {
        (try? repository.fetchCatalogCourseMatching(universityID: universityID, code: code)) != nil
    }

    func validateBatch(
        _ rules: [(rule: PrerequisiteRule, courseCode: String, courseID: UUID)],
        forUniversity universityName: String
    ) -> [UUID: ValidationResult] {
        var results: [UUID: ValidationResult] = [:]
        for item in rules {
            results[item.courseID] = validate(
                rule: item.rule,
                forUniversity: universityName,
                courseCode: item.courseCode
            )
        }
        return results
    }

    func suggestFixes(for invalidCode: String, university: String) -> [String] {
        _ = university
        guard let regex = Self.deptPrefixRegex,
              let match = regex.firstMatch(in: invalidCode, range: NSRange(invalidCode.startIndex..., in: invalidCode)),
              let deptRange = Range(match.range(at: 1), in: invalidCode) else {
            return []
        }

        let dept = String(invalidCode[deptRange])
        let courses = (try? repository.searchCatalogCourses(
            universityID: universityID,
            query: dept,
            limit: 5,
            performBackfill: false
        )) ?? []
        return courses.map(\.courseCode).sorted()
    }
}
