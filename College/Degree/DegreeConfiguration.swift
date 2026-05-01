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
    static let undergraduate = "Undergraduate"
    static let graduate = "Graduate"
    static let lawSchool = "Law School"
    static let dentalSchool = "Dental School"
    static let medicalSchool = "JSMBS Medical School"
    static let doctorateProfessional = "Doctorate / Professional"
    
    static let degreeLevels: [DegreeLevel] = [
        DegreeLevel(
            level: undergraduate,
            types: [
                "Bachelor of Science (BS)",
                "Bachelor of Arts (BA)",
                "Bachelor of Fine Arts (BFA)",
                "Bachelor of Engineering (BE)",
                "Associate Degree (AS/AA)"
            ]
        ),
        DegreeLevel(
            level: graduate,
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
            level: lawSchool,
            types: [
                "Juris Doctor (JD)",
                "Master of Laws (LLM)",
                "Doctor of Juridical Science (SJD)"
            ]
        ),
        DegreeLevel(
            level: dentalSchool,
            types: [
                "Doctor of Dental Surgery (DDS)",
                "Doctor of Dental Medicine (DMD)",
                "Advanced Dental Certificate"
            ]
        ),
        DegreeLevel(
            level: medicalSchool,
            types: [
                "Doctor of Medicine (MD)",
                "Doctor of Philosophy (PhD)",
                "Medical Certificate"
            ]
        ),
        DegreeLevel(
            level: doctorateProfessional,
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
        let canonical = canonicalLevel(level)
        return degreeLevels.first(where: { $0.level == canonical })?.types ?? []
    }
    
    /// Get all level names
    static var allLevels: [String] {
        return degreeLevels.map { $0.level }
    }
    
    /// Get class standing labels based on degree level
    static func classStandings(for level: String) -> [String] {
        switch canonicalLevel(level) {
        case undergraduate:
            return ["Freshman", "Sophomore", "Junior", "Senior"]
        case graduate, lawSchool, dentalSchool, medicalSchool:
            return ["1st Year", "2nd Year", "3rd Year"]
        case doctorateProfessional:
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
        let normalizedType = degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
        for level in degreeLevels {
            if level.types.contains(normalizedType) {
                return level.level
            }
        }
        return nil
    }
    
    /// Check if a degree level is undergraduate
    static func isUndergraduate(_ level: String) -> Bool {
        return canonicalLevel(level) == undergraduate
    }
    
    /// Check if a degree level is graduate
    static func isGraduate(_ level: String) -> Bool {
        let canonical = canonicalLevel(level)
        return canonical == graduate || canonical == lawSchool || canonical == dentalSchool || canonical == medicalSchool
    }
    
    /// Check if a degree level is doctorate
    static func isDoctorate(_ level: String) -> Bool {
        return canonicalLevel(level) == doctorateProfessional
    }

    /// Returns semantically-related levels for query expansion.
    static func familyLevels(for level: String) -> [String] {
        let canonical = canonicalLevel(level)
        switch canonical {
        case undergraduate:
            return [undergraduate]
        case graduate, lawSchool, dentalSchool, medicalSchool, doctorateProfessional:
            return [graduate, lawSchool, dentalSchool, medicalSchool, doctorateProfessional]
        default:
            return [canonical]
        }
    }

    /// Expands a selected level into a query set, filtered to levels that are actually available.
    static func queryLevels(for level: String, availableLevels: [String]) -> [String] {
        let canonicalAvailable: [String] = {
            let cleaned = availableLevels
                .map { canonicalLevel($0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if cleaned.isEmpty {
                return allLevels
            }
            return Array(Set(cleaned))
        }()

        let preferred = familyLevels(for: level)
        let filtered = preferred.filter { canonicalAvailable.contains($0) }
        if !filtered.isEmpty {
            return filtered
        }

        let selectedCanonical = canonicalLevel(level)
        if canonicalAvailable.contains(selectedCanonical) {
            return [selectedCanonical]
        }
        return [selectedCanonical]
    }

    static func canonicalLevel(_ level: String) -> String {
        let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty {
            return undergraduate
        }

        // Backward compatibility with legacy values previously stored in Core Data/UI.
        if lower == "graduate (masters)" || lower == "combined" {
            return graduate
        }
        if lower == "phd" {
            return doctorateProfessional
        }

        return trimmed
    }
}
