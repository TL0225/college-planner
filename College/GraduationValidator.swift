import Foundation
import CoreData

/// Validates if student meets all degree requirements for graduation
class GraduationValidator {
    private let coreDataManager: CoreDataManager
    
    init(coreDataManager: CoreDataManager) {
        self.coreDataManager = coreDataManager
    }
    
    // MARK: - Main Validation
    
    /// Check if student is on track to graduate
    func validateGraduationReadiness(
        for plan: PlanEntity,
        university: UniversityEntity
    ) -> GraduationValidationResult {
        
        guard let major = plan.major,
              let degreeType = plan.type else {
            return GraduationValidationResult(
                ready: false,
                overallProgress: 0.0,
                categoryResults: [],
                violations: [.missingInfo("Major or degree type not set")]
            )
        }
        
        // Get degree requirements for this major
        let requirements = getDegreeRequirements(
            for: major,
            degreeType: degreeType,
            university: university
        )
        
        guard !requirements.isEmpty else {
            return GraduationValidationResult(
                ready: false,
                overallProgress: 0.0,
                categoryResults: [],
                violations: [.missingInfo("No degree requirements found for \(major)")]
            )
        }
        
        // Get all courses in the plan
        let allCourses = getAllCourses(from: plan)
        let completedCourses = allCourses.filter { $0.isCompleted }
        
        // Validate each requirement category
        var categoryResults: [CategoryResult] = []
        var violations: [PolicyViolation] = []
        
        for requirement in requirements {
            let result = validateRequirementCategory(
                requirement: requirement,
                courses: allCourses,
                completedCourses: completedCourses
            )
            
            categoryResults.append(result)
            violations.append(contentsOf: result.violations)
        }

        func isUndergraduateDegreeType(_ raw: String) -> Bool {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if t.isEmpty { return false }
            // Common undergrad abbreviations.
            if ["BA", "BS", "BFA", "BBA", "BM", "BENG", "BE"].contains(t) { return true }
            // Also handle full strings like "Bachelor of Science" if they appear.
            if t.contains("BACHELOR") { return true }
            // Conservative fallback: starts with B and is short.
            if t.hasPrefix("B") && t.count <= 6 { return true }
            return false
        }

        // Manual GenEd bucket (course-count based; double-dips allowed)
        // Applies only to Undergraduate majors.
        if isUndergraduateDegreeType(degreeType) {
            let genEdAssignedCourses = allCourses.filter { $0.countsTowardGenEd }
            let genEdCompletedCourses = genEdAssignedCourses.filter { $0.isCompleted }
            let genEdSatisfiedCodes: [String] = genEdCompletedCourses
                .compactMap { $0.code }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }

            let genEdProgress = genEdAssignedCourses.isEmpty
                ? 0.0
                : Double(genEdCompletedCourses.count) / Double(genEdAssignedCourses.count)

            categoryResults.append(
                CategoryResult(
                    category: "\((university.name ?? "University")) General Education",
                    creditsRequired: 0,
                    creditsCompleted: 0,
                    coursesSatisfied: genEdSatisfiedCodes,
                    progress: genEdProgress,
                    violations: [],
                    courseCountRequired: genEdAssignedCourses.count,
                    courseCountCompleted: genEdCompletedCourses.count
                )
            )
        }
        
        // Check school policies
        if let policies = university.value(forKey: "policies") as? SchoolPolicies {
            let policyViolations = validatePolicies(
                policies: policies,
                courses: allCourses,
                plan: plan
            )
            violations.append(contentsOf: policyViolations)
        }
        
        // Calculate overall progress
        let totalRequired = categoryResults.reduce(0) { $0 + $1.creditsRequired }
        let totalCompleted = categoryResults.reduce(0) { $0 + $1.creditsCompleted }
        let overallProgress = totalRequired > 0 ? Double(totalCompleted) / Double(totalRequired) : 0.0
        
        let ready = violations.isEmpty && overallProgress >= 1.0
        
        return GraduationValidationResult(
            ready: ready,
            overallProgress: overallProgress,
            categoryResults: categoryResults,
            violations: violations
        )
    }
    
    // MARK: - Requirement Validation
    
    private func validateRequirementCategory(
        requirement: DegreeRequirementEntity,
        courses: [CourseEntity],
        completedCourses: [CourseEntity]
    ) -> CategoryResult {
        
        let creditsRequired = Int(requirement.creditsRequired)
        var creditsCompleted = 0
        var coursesSatisfied: [String] = []
        var violations: [PolicyViolation] = []
        
        func normalize(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        let completedByCode: [String: CourseEntity] = {
            var dict: [String: CourseEntity] = [:]
            for c in completedCourses {
                let code = normalize(c.code ?? "")
                if !code.isEmpty { dict[code] = c }
            }
            return dict
        }()

        // 1) Select-from requirements (OR / choose N)
        let selectCount = Int(requirement.selectCount)
        if selectCount > 0 {
            let selectCodes: [String] = {
                if let json = requirement.selectFromDetailedJSON,
                   let data = json.data(using: .utf8),
                   let detailed = try? JSONDecoder().decode([CourseDetail].self, from: data),
                   !detailed.isEmpty {
                    return detailed.map { normalize($0.code) }
                }
                if let json = requirement.selectFromJSON,
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String].self, from: data),
                   !decoded.isEmpty {
                    return decoded.map(normalize)
                }
                return []
            }()

            let completedMatches: [CourseEntity] = selectCodes.compactMap { completedByCode[$0] }
            for c in completedMatches.prefix(selectCount) {
                creditsCompleted += Int(c.credits)
                coursesSatisfied.append(normalize(c.code ?? ""))
            }

            if completedMatches.count < selectCount {
                let missing = selectCount - completedMatches.count
                violations.append(.missingInfo("\(requirement.requirementCategory ?? ""): select \(missing) more course(s)"))
            }
        } else {
            // 2) Required courses
            let requiredCodes: [String] = {
                if let json = requirement.requiredCoursesDetailedJSON,
                   let data = json.data(using: .utf8),
                   let detailed = try? JSONDecoder().decode([CourseDetail].self, from: data),
                   !detailed.isEmpty {
                    return detailed.map { normalize($0.code) }
                }
                if let requiredCoursesString = requirement.requiredCourses {
                    return requiredCoursesString
                        .split(separator: ",")
                        .map { normalize(String($0)) }
                        .filter { !$0.isEmpty }
                }
                return []
            }()

            if !requiredCodes.isEmpty {
                for code in requiredCodes {
                    if let matchingCourse = completedByCode[code] {
                        creditsCompleted += Int(matchingCourse.credits)
                        coursesSatisfied.append(code)
                    } else {
                        violations.append(.missingRequiredCourse(code, category: requirement.requirementCategory ?? ""))
                    }
                }
            } else {
                // If no specific courses required, count any completed courses in category
                for course in completedCourses {
                    if let dept = requirement.requirementCategory {
                        if normalize(course.code ?? "").hasPrefix(normalize(dept)) {
                            creditsCompleted += Int(course.credits)
                            coursesSatisfied.append(normalize(course.code ?? ""))
                        }
                    }
                }
            }
        }
        
        // Check if credit requirement is met
        if creditsCompleted < creditsRequired {
            let deficit = creditsRequired - creditsCompleted
            violations.append(.insufficientCredits(
                category: requirement.requirementCategory ?? "",
                required: creditsRequired,
                completed: creditsCompleted,
                deficit: deficit
            ))
        }
        
        return CategoryResult(
            category: requirement.requirementCategory ?? "Unknown",
            creditsRequired: creditsRequired,
            creditsCompleted: creditsCompleted,
            coursesSatisfied: coursesSatisfied,
            progress: creditsRequired > 0 ? Double(creditsCompleted) / Double(creditsRequired) : 0.0,
            violations: violations
        )
    }
    
    // MARK: - Policy Validation
    
    private func validatePolicies(
        policies: SchoolPolicies,
        courses: [CourseEntity],
        plan: PlanEntity
    ) -> [PolicyViolation] {
        
        var violations: [PolicyViolation] = []
        
        // Check transfer credit limit
        if let transferLimit = policies.transferCreditLimit {
            let transferCredits = courses.filter { $0.status == "Transfer" }.reduce(0) { $0 + Int($1.credits) }
            
            if transferCredits > transferLimit {
                violations.append(.transferCreditExceeded(
                    limit: transferLimit,
                    actual: transferCredits,
                    excess: transferCredits - transferLimit
                ))
            }
        }
        
        // Check minor transfer limit
        if let minorLimit = policies.minorTransferLimit,
           plan.minor != nil {
            let minorTransferCredits = courses.filter { course in
                course.status == "Transfer" && isMinorCourse(course, minor: plan.minor)
            }.reduce(0) { $0 + Int($1.credits) }
            
            if minorTransferCredits > minorLimit {
                violations.append(.minorTransferExceeded(
                    limit: minorLimit,
                    actual: minorTransferCredits
                ))
            }
        }
        
        // Check semester credit limits
        if let maxPerSemester = policies.maxCreditsPerSemester {
            let semesters = plan.semesters as? Set<SemesterEntity> ?? []
            
            for semester in semesters {
                let semesterCourses = semester.courses as? Set<CourseEntity> ?? []
                let semesterCredits = semesterCourses.reduce(0) { $0 + Int($1.credits) }
                
                if semesterCredits > maxPerSemester {
                    violations.append(.semesterOverload(
                        semester: semester.name ?? "Unknown",
                        limit: maxPerSemester,
                        actual: semesterCredits
                    ))
                }
            }
        }
        
        return violations
    }
    
    // MARK: - Helper Methods
    
    private func getDegreeRequirements(
        for major: String,
        degreeType: String,
        university: UniversityEntity
    ) -> [DegreeRequirementEntity] {
        
        guard let requirements = university.degreeRequirements as? Set<DegreeRequirementEntity> else {
            return []
        }
        
        return requirements.filter { requirement in
            requirement.major == major && requirement.degreeType == degreeType
        }
    }
    
    private func getAllCourses(from plan: PlanEntity) -> [CourseEntity] {
        guard let semesters = plan.semesters as? Set<SemesterEntity> else {
            return []
        }
        
        var allCourses: [CourseEntity] = []
        for semester in semesters {
            if let courses = semester.courses as? Set<CourseEntity> {
                allCourses.append(contentsOf: courses)
            }
        }
        
        return allCourses
    }
    
    private func isMinorCourse(_ course: CourseEntity, minor: String?) -> Bool {
        guard let minor = minor else { return false }
        
        // Simple heuristic: course code starts with minor abbreviation
        let minorPrefix = minor.prefix(4).uppercased()
        return course.code?.uppercased().hasPrefix(minorPrefix) == true
    }
    
    // MARK: - Progress Tracking
    
    /// Get detailed progress breakdown by category
    func getProgressBreakdown(for plan: PlanEntity, university: UniversityEntity) -> ProgressBreakdown {
        let validation = validateGraduationReadiness(for: plan, university: university)
        
        let totalCreditsRequired = validation.categoryResults.reduce(0) { $0 + $1.creditsRequired }
        let totalCreditsCompleted = validation.categoryResults.reduce(0) { $0 + $1.creditsCompleted }
        let totalCreditsRemaining = max(0, totalCreditsRequired - totalCreditsCompleted)
        
        return ProgressBreakdown(
            totalCreditsRequired: totalCreditsRequired,
            totalCreditsCompleted: totalCreditsCompleted,
            totalCreditsRemaining: totalCreditsRemaining,
            overallProgress: validation.overallProgress,
            categoryBreakdown: validation.categoryResults,
            onTrack: validation.ready || validation.overallProgress > 0.5
        )
    }
}

// MARK: - Result Structures

struct GraduationValidationResult {
    let ready: Bool
    let overallProgress: Double // 0.0 to 1.0
    let categoryResults: [CategoryResult]
    let violations: [PolicyViolation]
}

struct CategoryResult {
    let category: String
    let creditsRequired: Int
    let creditsCompleted: Int
    let coursesSatisfied: [String]
    let progress: Double // 0.0 to 1.0
    let violations: [PolicyViolation]

    // Optional course-count metric (used for manual GenEd)
    let courseCountRequired: Int?
    let courseCountCompleted: Int?

    init(
        category: String,
        creditsRequired: Int,
        creditsCompleted: Int,
        coursesSatisfied: [String],
        progress: Double,
        violations: [PolicyViolation],
        courseCountRequired: Int? = nil,
        courseCountCompleted: Int? = nil
    ) {
        self.category = category
        self.creditsRequired = creditsRequired
        self.creditsCompleted = creditsCompleted
        self.coursesSatisfied = coursesSatisfied
        self.progress = progress
        self.violations = violations
        self.courseCountRequired = courseCountRequired
        self.courseCountCompleted = courseCountCompleted
    }
}

struct ProgressBreakdown {
    let totalCreditsRequired: Int
    let totalCreditsCompleted: Int
    let totalCreditsRemaining: Int
    let overallProgress: Double
    let categoryBreakdown: [CategoryResult]
    let onTrack: Bool
}

enum PolicyViolation: Equatable {
    case missingRequiredCourse(String, category: String)
    case insufficientCredits(category: String, required: Int, completed: Int, deficit: Int)
    case transferCreditExceeded(limit: Int, actual: Int, excess: Int)
    case minorTransferExceeded(limit: Int, actual: Int)
    case semesterOverload(semester: String, limit: Int, actual: Int)
    case missingInfo(String)
    
    var description: String {
        switch self {
        case .missingRequiredCourse(let course, let category):
            return "Missing required course: \(course) (\(category))"
        case .insufficientCredits(let category, let required, let completed, let deficit):
            return "\(category): Need \(deficit) more credits (\(completed)/\(required))"
        case .transferCreditExceeded(let limit, let actual, let excess):
            return "Transfer credits exceed limit: \(actual)/\(limit) (\(excess) over)"
        case .minorTransferExceeded(let limit, let actual):
            return "Minor transfer credits exceed limit: \(actual)/\(limit)"
        case .semesterOverload(let semester, let limit, let actual):
            return "\(semester): \(actual) credits exceeds limit of \(limit)"
        case .missingInfo(let info):
            return "Missing information: \(info)"
        }
    }
    
    var severity: ViolationSeverity {
        switch self {
        case .missingRequiredCourse, .insufficientCredits:
            return .critical
        case .transferCreditExceeded, .minorTransferExceeded, .semesterOverload:
            return .warning
        case .missingInfo:
            return .info
        }
    }
}

enum ViolationSeverity {
    case critical // Blocks graduation
    case warning  // Policy violation but may have exceptions
    case info     // Informational only
}
