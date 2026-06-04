// PrerequisiteValidator.swift
// Feature: Degree
// Purpose: Degree module — PrerequisiteValidationResult.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Engine for validating course prerequisites and checking if student meets requirements
class PrerequisiteValidator {
    private let collegePersistence: CollegePersistence

    init(collegePersistence: CollegePersistence) {
        self.collegePersistence = collegePersistence
    }
    
    // MARK: - Main Validation Methods
    
    /// Check if student meets prerequisites for a course
    func validatePrerequisites(
        for catalogCourse: CourseCatalog,
        completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        validatePrerequisites(
            prerequisiteRulesJSON: catalogCourse.prerequisiteRulesJSON,
            completedCourses: completedCourses
        )
    }

    private func validatePrerequisites(
        prerequisiteRulesJSON rulesJSON: String?,
        completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        // Parse prerequisite rules from JSON
        guard let rulesJSON,
              let rulesData = rulesJSON.data(using: .utf8),
              let prerequisiteRule = try? JSONDecoder().decode(PrerequisiteRule.self, from: rulesData)
        else {
            // No prerequisites or couldn't parse
            return PrerequisiteValidationResult(met: true, missingCourses: [], message: "No prerequisites")
        }
        
        // Evaluate the rule tree
        return evaluateRule(prerequisiteRule, with: completedCourses)
    }
    
    /// Evaluate a prerequisite rule recursively
    private func evaluateRule(
        _ rule: PrerequisiteRule,
        with completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        
        switch rule {
        case .course(let requirement):
            return evaluateCourseRequirement(requirement, with: completedCourses)
            
        case .and(let rules):
            return evaluateAndRules(rules, with: completedCourses)
            
        case .or(let rules):
            return evaluateOrRules(rules, with: completedCourses)
        }
    }
    
    // MARK: - Rule Evaluation
    
    private func evaluateCourseRequirement(
        _ requirement: CourseRequirement,
        with completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        
        // Find if student has completed this course
        let matchingCourse = completedCourses.first { course in
            course.code == requirement.courseCode && course.isCompleted
        }
        
        guard let course = matchingCourse else {
            return PrerequisiteValidationResult(
                met: false,
                missingCourses: [requirement.courseCode],
                message: "Missing \(requirement.courseCode)"
            )
        }
        
        // Check minimum grade if specified
        if let minGrade = requirement.minGrade,
           let studentGrade = course.grade {
            let meetsGrade = compareGrades(studentGrade, meetsMinimum: minGrade)
            
            if !meetsGrade {
                return PrerequisiteValidationResult(
                    met: false,
                    missingCourses: [],
                    message: "\(requirement.courseCode) requires minimum grade \(minGrade), got \(studentGrade)"
                )
            }
        }
        
        return PrerequisiteValidationResult(met: true, missingCourses: [], message: "✓ \(requirement.courseCode)")
    }
    
    private func evaluateAndRules(
        _ rules: [PrerequisiteRule],
        with completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        
        var allMissingCourses: [String] = []
        var messages: [String] = []
        
        for rule in rules {
            let result = evaluateRule(rule, with: completedCourses)
            
            if !result.met {
                allMissingCourses.append(contentsOf: result.missingCourses)
                messages.append(result.message)
            }
        }
        
        let allMet = allMissingCourses.isEmpty
        let message = allMet ? "All requirements met" : "Missing: " + messages.joined(separator: " AND ")
        
        return PrerequisiteValidationResult(
            met: allMet,
            missingCourses: allMissingCourses,
            message: message
        )
    }
    
    private func evaluateOrRules(
        _ rules: [PrerequisiteRule],
        with completedCourses: [PlannerCourse]
    ) -> PrerequisiteValidationResult {
        
        var allMissingCourses: [String] = []
        var messages: [String] = []
        
        for rule in rules {
            let result = evaluateRule(rule, with: completedCourses)
            
            if result.met {
                // At least one option is satisfied
                return PrerequisiteValidationResult(met: true, missingCourses: [], message: result.message)
            }
            
            allMissingCourses.append(contentsOf: result.missingCourses)
            messages.append(result.message)
        }
        
        // None of the options were met
        let message = "Need one of: " + messages.joined(separator: " OR ")
        
        return PrerequisiteValidationResult(
            met: false,
            missingCourses: Array(Set(allMissingCourses)), // Remove duplicates
            message: message
        )
    }
    
    // MARK: - Grade Comparison
    
    private func compareGrades(_ studentGrade: String, meetsMinimum minGrade: String) -> Bool {
        let gradeValues: [String: Double] = [
            "A+": 4.0, "A": 4.0, "A-": 3.7,
            "B+": 3.3, "B": 3.0, "B-": 2.7,
            "C+": 2.3, "C": 2.0, "C-": 1.7,
            "D+": 1.3, "D": 1.0, "D-": 0.7,
            "F": 0.0
        ]
        
        guard let studentValue = gradeValues[studentGrade.uppercased()],
              let minimumValue = gradeValues[minGrade.uppercased()] else {
            return true // Can't compare, assume it's okay
        }
        
        return studentValue >= minimumValue
    }
    
    // MARK: - Convenience Methods
    
    /// Get all completed courses for a student
    func getCompletedCourses(for plan: PlannerPlan) -> [PlannerCourse] {
        plan.semestersArray
            .flatMap(\.coursesArray)
            .filter(\.isCompleted)
    }
    
    /// Check prerequisites for multiple courses at once
    func validateMultiple(
        courses: [CourseCatalogEntity],
        completedCourses: [PlannerCourse]
    ) -> [String: PrerequisiteValidationResult] {
        
        var results: [String: PrerequisiteValidationResult] = [:]
        
        for course in courses {
            let result = validatePrerequisites(for: course, completedCourses: completedCourses)
            results[course.courseCode] = result
        }
        
        return results
    }
    
    /// Find courses that are now available (prerequisites met)
    func findAvailableCourses(
        from catalog: [CourseCatalogEntity],
        completedCourses: [PlannerCourse]
    ) -> [CourseCatalogEntity] {
        
        return catalog.filter { course in
            let result = validatePrerequisites(for: course, completedCourses: completedCourses)
            return result.met
        }
    }
    
    /// Find courses that are blocked (prerequisites not met)
    func findBlockedCourses(
        from catalog: [CourseCatalogEntity],
        completedCourses: [PlannerCourse]
    ) -> [(course: CourseCatalogEntity, reason: PrerequisiteValidationResult)] {
        
        var blocked: [(CourseCatalogEntity, PrerequisiteValidationResult)] = []
        
        for course in catalog {
            let result = validatePrerequisites(for: course, completedCourses: completedCourses)
            if !result.met {
                blocked.append((course, result))
            }
        }
        
        return blocked
    }
}

// MARK: - Validation Result

struct PrerequisiteValidationResult {
    let met: Bool
    let missingCourses: [String]
    let message: String
}

// MARK: - Extensions

extension PrerequisiteRule {
    /// Convert to human-readable string
    func toReadableString() -> String {
        switch self {
        case .course(let requirement):
            if let minGrade = requirement.minGrade {
                return "\(requirement.courseCode) (min grade: \(minGrade))"
            }
            return requirement.courseCode
            
        case .and(let rules):
            let courseStrings = rules.map { $0.toReadableString() }
            return courseStrings.joined(separator: " AND ")
            
        case .or(let rules):
            let courseStrings = rules.map { $0.toReadableString() }
            return "(" + courseStrings.joined(separator: " OR ") + ")"
        }
    }
    
    /// Get all course codes mentioned in the rule tree
    func getAllCourseCodes() -> [String] {
        switch self {
        case .course(let requirement):
            return [requirement.courseCode]
            
        case .and(let rules), .or(let rules):
            return rules.flatMap { $0.getAllCourseCodes() }
        }
    }
}
