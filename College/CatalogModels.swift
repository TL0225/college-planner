import Foundation

// MARK: - School Manifest (schools.json)

struct SchoolManifest: Codable, Identifiable {
    let id: String
    let name: String
    let shortName: String?
    let profileURL: String
    let catalogURL: String?  // Direct URL to school's catalog website
    let catalogFormat: String // "acalog", "banner", "custom"
    let lastUpdated: Date
    let coursesCount: Int
    let verified: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case shortName = "short_name"
        case profileURL = "profile_url"
        case catalogURL = "catalog_url"
        case catalogFormat = "catalog_format"
        case lastUpdated = "last_updated"
        case coursesCount = "courses_count"
        case verified
    }
}

// MARK: - School Profile (rutgers_nb.json)

struct SchoolProfile: Codable {
    let schoolID: String
    let schoolName: String
    let catalogURL: String
    let version: String
    let lastUpdated: Date
    let courses: [CatalogCourse]
    let degreeRequirements: [DegreeRequirement]
    let policies: SchoolPolicies
    
    enum CodingKeys: String, CodingKey {
        case schoolID = "school_id"
        case schoolName = "school_name"
        case catalogURL = "catalog_url"
        case version
        case lastUpdated = "last_updated"
        case courses
        case degreeRequirements = "degree_requirements"
        case policies
    }
}

// MARK: - Catalog Course

nonisolated struct CatalogCourse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let courseCode: String
    let title: String
    let description: String?
    let credits: Int
    let department: String?
    let prerequisites: PrerequisiteRule?
    let prerequisiteText: String? // Raw text for scraper output
    let corequisites: [String]?
    let typicallyOffered: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, courseCode = "course_code"
        case title, description, credits, department
        case prerequisites, prerequisiteText = "prerequisite_text", corequisites
        case typicallyOffered = "typically_offered"
    }
    
    // Manual initializer for programmatic creation
    nonisolated init(
        id: UUID = UUID(),
        courseCode: String,
        title: String,
        description: String? = nil,
        credits: Int,
        department: String? = nil,
        prerequisites: PrerequisiteRule? = nil,
        prerequisiteText: String? = nil,
        corequisites: [String]? = nil,
        typicallyOffered: [String]? = nil
    ) {
        self.id = id
        self.courseCode = courseCode
        self.title = title
        self.description = description
        self.credits = credits
        self.department = department
        self.prerequisites = prerequisites
        self.prerequisiteText = prerequisiteText
        self.corequisites = corequisites
        self.typicallyOffered = typicallyOffered
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        courseCode = try container.decode(String.self, forKey: .courseCode)
        title = try container.decode(String.self, forKey: .title)
        description = try? container.decode(String.self, forKey: .description)
        credits = try container.decode(Int.self, forKey: .credits)
        department = try? container.decode(String.self, forKey: .department)
        prerequisites = try? container.decode(PrerequisiteRule.self, forKey: .prerequisites)
        prerequisiteText = try? container.decode(String.self, forKey: .prerequisiteText)
        corequisites = try? container.decode([String].self, forKey: .corequisites)
        typicallyOffered = try? container.decode([String].self, forKey: .typicallyOffered)
    }
}

// MARK: - Prerequisite Rules (Recursive Structure)

nonisolated enum PrerequisiteRule: Codable, Equatable, Hashable, Sendable {
    case course(CourseRequirement)
    case and([PrerequisiteRule])
    case or([PrerequisiteRule])
    
    enum CodingKeys: String, CodingKey {
        case type, course, rules
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type.lowercased() {
        case "course":
            let course = try container.decode(CourseRequirement.self, forKey: .course)
            self = .course(course)
        case "and":
            let rules = try container.decode([PrerequisiteRule].self, forKey: .rules)
            self = .and(rules)
        case "or":
            let rules = try container.decode([PrerequisiteRule].self, forKey: .rules)
            self = .or(rules)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown prerequisite type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .course(let requirement):
            try container.encode("course", forKey: .type)
            try container.encode(requirement, forKey: .course)
        case .and(let rules):
            try container.encode("and", forKey: .type)
            try container.encode(rules, forKey: .rules)
        case .or(let rules):
            try container.encode("or", forKey: .type)
            try container.encode(rules, forKey: .rules)
        }
    }
}

nonisolated struct CourseRequirement: Codable, Equatable, Hashable, Sendable {
    let courseCode: String
    let minGrade: String? // "B", "C+", etc.
    
    enum CodingKeys: String, CodingKey {
        case courseCode = "course_code"
        case minGrade = "min_grade"
    }
}

// MARK: - Degree Requirements

/// Detailed course information extracted from catalog
nonisolated struct CourseDetail: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let code: String // "CSE 113"
    let title: String? // "Foundations of Computer Science I"
    let credits: String? // "3" or "1-6"
    
    init(code: String, title: String? = nil, credits: String? = nil) {
        self.id = UUID()
        self.code = code
        self.title = title
        self.credits = credits
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }
    
    static func == (lhs: CourseDetail, rhs: CourseDetail) -> Bool {
        lhs.code == rhs.code
    }
}

nonisolated struct DegreeRequirement: Codable, Identifiable, Sendable {
    let id: UUID
    let degreeType: String // "Bachelor of Science"
    let major: String
    let category: String // "Core", "Electives", "General Education"
    let requiredCourses: [String]? // Legacy: course codes only
    let requiredCoursesDetailed: [CourseDetail]? // New: full course details
    let creditsRequired: Int
    let description: String?
    let selectFrom: [String]? // Legacy: course codes only
    let selectFromDetailed: [CourseDetail]? // New: full course details
    let selectCount: Int? // Number to select from selectFrom
    
    enum CodingKeys: String, CodingKey {
        case id
        case degreeType = "degree_type"
        case major, category
        case requiredCourses = "required_courses"
        case requiredCoursesDetailed = "required_courses_detailed"
        case creditsRequired = "credits_required"
        case description
        case selectFrom = "select_from"
        case selectFromDetailed = "select_from_detailed"
        case selectCount = "select_count"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        degreeType = try container.decode(String.self, forKey: .degreeType)
        major = try container.decode(String.self, forKey: .major)
        category = try container.decode(String.self, forKey: .category)
        requiredCourses = try? container.decode([String].self, forKey: .requiredCourses)
        requiredCoursesDetailed = try? container.decode([CourseDetail].self, forKey: .requiredCoursesDetailed)
        creditsRequired = try container.decode(Int.self, forKey: .creditsRequired)
        description = try? container.decode(String.self, forKey: .description)
        selectFrom = try? container.decode([String].self, forKey: .selectFrom)
        selectFromDetailed = try? container.decode([CourseDetail].self, forKey: .selectFromDetailed)
        selectCount = try? container.decode(Int.self, forKey: .selectCount)
    }
    
    // Manual initializer for programmatic creation
    init(
        id: UUID = UUID(),
        degreeType: String,
        major: String,
        category: String,
        requiredCourses: [String]? = nil,
        requiredCoursesDetailed: [CourseDetail]? = nil,
        creditsRequired: Int,
        description: String? = nil,
        selectFrom: [String]? = nil,
        selectFromDetailed: [CourseDetail]? = nil,
        selectCount: Int? = nil
    ) {
        self.id = id
        self.degreeType = degreeType
        self.major = major
        self.category = category
        self.requiredCourses = requiredCourses
        self.requiredCoursesDetailed = requiredCoursesDetailed
        self.creditsRequired = creditsRequired
        self.description = description
        self.selectFrom = selectFrom
        self.selectFromDetailed = selectFromDetailed
        self.selectCount = selectCount
    }
}

// MARK: - School Policies

struct SchoolPolicies: Codable {
    let transferCreditLimit: Int?
    let minorTransferLimit: Int?
    let maxCreditsPerSemester: Int?
    let minCreditsForFullTime: Int?
    let gradeForCredit: String? // Minimum grade to receive credit (e.g., "D")
    let repeatCoursePolicy: String?
    
    enum CodingKeys: String, CodingKey {
        case transferCreditLimit = "transfer_credit_limit"
        case minorTransferLimit = "minor_transfer_limit"
        case maxCreditsPerSemester = "max_credits_per_semester"
        case minCreditsForFullTime = "min_credits_full_time"
        case gradeForCredit = "grade_for_credit"
        case repeatCoursePolicy = "repeat_course_policy"
    }
}

// MARK: - Policy Correction (for GitHub submission)

struct PolicyCorrection: Codable {
    let schoolID: String
    let policyName: String
    let currentValue: String
    let correctedValue: String
    let source: String?
    let submittedBy: String
    let submittedDate: Date
    
    enum CodingKeys: String, CodingKey {
        case schoolID = "school_id"
        case policyName = "policy_name"
        case currentValue = "current_value"
        case correctedValue = "corrected_value"
        case source
        case submittedBy = "submitted_by"
        case submittedDate = "submitted_date"
    }
}

// MARK: - Scraper Recipe

struct ScraperRecipe: Codable {
    let id: String
    let name: String
    let format: String // "acalog", "banner"
    let script: String // JavaScript code
    let selectors: [String: String]
    let version: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, format, script, selectors, version
    }
}
