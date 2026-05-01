import Foundation
import CoreData

/// Validates prerequisite rules against the course catalog during import
/// Ensures all referenced courses actually exist in the database
class CatalogPrerequisiteValidator {
    
    private let context: NSManagedObjectContext

    private static let deptPrefixRegex = try? NSRegularExpression(pattern: #"^([A-Z]{2,4})"#)
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    // MARK: - Validation Results
    
    struct ValidationResult {
        let isValid: Bool
        let invalidCourseCodes: [String]
        let warnings: [String]
        let confidence: ValidationConfidence
        
        var needsManualReview: Bool {
            return confidence == .invalid || confidence == .needsReview
        }
    }
    
    enum ValidationConfidence {
        case valid          // All courses exist
        case partiallyValid // Some courses missing but rule makes sense
        case invalid        // Multiple courses missing or logic broken
        case needsReview    // Non-course prerequisites (permission, etc.)
    }
    
    // MARK: - Main Validation Method
    
    /// Validate a prerequisite rule against the course catalog
    func validate(
        rule: PrerequisiteRule,
        forUniversity universityName: String,
        courseCode: String
    ) -> ValidationResult {
        
        var invalidCodes: [String] = []
        var warnings: [String] = []
        
        // Extract all course codes from the rule
        let referencedCodes = extractCourseCodes(from: rule)
        
        // Check if each course exists in the catalog
        for code in referencedCodes {
            if !courseExists(code: code, university: universityName) {
                invalidCodes.append(code)
                warnings.append("Course \(code) not found in \(universityName) catalog")
            }
        }
        
        // Additional validation checks
        
        // Check for circular dependencies
        if referencedCodes.contains(courseCode) {
            warnings.append("Circular prerequisite: \(courseCode) requires itself")
        }
        
        // Check for empty rules
        if referencedCodes.isEmpty {
            return ValidationResult(
                isValid: false,
                invalidCourseCodes: [],
                warnings: ["No course codes found in prerequisite rule"],
                confidence: .needsReview
            )
        }
        
        // Determine confidence level
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
    
    // MARK: - Helper Methods
    
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
    
    private func courseExists(code: String, university: String) -> Bool {
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(
            format: "courseCode == %@ AND university.name == %@",
            code, university
        )
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("[CatalogValidator] Error checking course existence: \(error)")
            return false
        }
    }
    
    // MARK: - Batch Validation
    
    /// Validate multiple prerequisite rules at once
    func validateBatch(
        _ rules: [(rule: PrerequisiteRule, courseCode: String, courseID: UUID)],
        forUniversity universityName: String
    ) -> [UUID: ValidationResult] {
        
        var results: [UUID: ValidationResult] = [:]
        
        for item in rules {
            let result = validate(
                rule: item.rule,
                forUniversity: universityName,
                courseCode: item.courseCode
            )
            results[item.courseID] = result
        }
        
        return results
    }
    
    // MARK: - Auto-Fix Suggestions
    
    /// Attempt to find similar course codes for invalid prerequisites
    func suggestFixes(
        for invalidCode: String,
        university: String
    ) -> [String] {
        
                // Extract department prefix (e.g., "CS" from "CS 1110")
                guard let regex = Self.deptPrefixRegex,
              let match = regex.firstMatch(in: invalidCode, range: NSRange(invalidCode.startIndex..., in: invalidCode)),
              let deptRange = Range(match.range(at: 1), in: invalidCode) else {
            return []
        }
        
        let dept = String(invalidCode[deptRange])
        
        // Search for similar courses in the same department
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(
            format: "department == %@ AND university.name == %@",
            dept, university
        )
        request.fetchLimit = 5
        request.sortDescriptors = [NSSortDescriptor(key: "courseCode", ascending: true)]
        
        do {
            let courses = try context.fetch(request)
            return courses.compactMap { $0.courseCode }
        } catch {
            print("[CatalogValidator] Error fetching suggestions: \(error)")
            return []
        }
    }
}
