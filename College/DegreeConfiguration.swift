import Foundation

// MARK: - Degree Configuration Data

struct DegreeLevel: Identifiable, Codable {
    let id = UUID()
    let level: String
    let types: [String]
    
    enum CodingKeys: String, CodingKey {
        case level, types
    }
}

struct DegreeConfiguration {
    
    static let degreeLevels: [DegreeLevel] = [
        DegreeLevel(
            level: "Undergraduate",
            types: [
                "Bachelor of Science (BS)",
                "Bachelor of Arts (BA)",
                "Bachelor of Fine Arts (BFA)",
                "Bachelor of Engineering (BE)",
                "Associate Degree (AS/AA)"
            ]
        ),
        DegreeLevel(
            level: "Graduate (Masters)",
            types: [
                "Master of Science (MS)",
                "Master of Arts (MA)",
                "Master of Business Administration (MBA)",
                "Master of Engineering (MEng)",
                "Master of Fine Arts (MFA)",
                "Master of Public Administration (MPA)",
                "Master of Social Work (MSW)",
                "Master of Education (MEd)"
            ]
        ),
        DegreeLevel(
            level: "Doctorate / Professional",
            types: [
                "Doctor of Philosophy (PhD)",
                "Doctor of Medicine (MD)",
                "Juris Doctor (JD)",
                "Doctor of Education (EdD)",
                "Doctor of Dental Surgery (DDS)",
                "Doctor of Veterinary Medicine (DVM)",
                "Doctor of Pharmacy (PharmD)"
            ]
        )
    ]
    
    /// Get degree types for a specific level
    static func types(for level: String) -> [String] {
        return degreeLevels.first(where: { $0.level == level })?.types ?? []
    }
    
    /// Get all level names
    static var allLevels: [String] {
        return degreeLevels.map { $0.level }
    }
    
    /// Get class standing labels based on degree level
    static func classStandings(for level: String) -> [String] {
        switch level {
        case "Undergraduate":
            return ["Freshman", "Sophomore", "Junior", "Senior"]
        case "Graduate (Masters)":
            return ["1st Year", "2nd Year", "3rd Year"]
        case "Doctorate / Professional":
            return ["1st Year", "2nd Year", "3rd Year", "Candidate", "ABD (All But Dissertation)"]
        default:
            return ["Freshman", "Sophomore", "Junior", "Senior"]
        }
    }
    
    /// Extract short form from full degree type (e.g., "Bachelor of Science (BS)" -> "BS")
    static func shortForm(from fullType: String) -> String {
        if let match = fullType.range(of: "\\(([A-Z/]+)\\)", options: .regularExpression) {
            let matched = String(fullType[match])
            return matched.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        }
        return fullType
    }
    
    /// Get degree level from degree type (reverse lookup)
    static func level(for degreeType: String) -> String? {
        for level in degreeLevels {
            if level.types.contains(degreeType) {
                return level.level
            }
        }
        return nil
    }
    
    /// Check if a degree level is undergraduate
    static func isUndergraduate(_ level: String) -> Bool {
        return level == "Undergraduate"
    }
    
    /// Check if a degree level is graduate
    static func isGraduate(_ level: String) -> Bool {
        return level == "Graduate (Masters)"
    }
    
    /// Check if a degree level is doctorate
    static func isDoctorate(_ level: String) -> Bool {
        return level == "Doctorate / Professional"
    }
}
