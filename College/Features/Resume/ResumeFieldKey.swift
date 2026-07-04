// ResumeFieldKey.swift
// Feature: Resume
// Purpose: Stable keys for resume-only field overrides layered on Profile snapshot data.

import Foundation

enum ResumePersonalField: String, Codable, Sendable, Hashable, CaseIterable {
    case name
    case pronouns
    case email
    case phone
    case address
}

enum ResumeExperienceField: String, Codable, Sendable, Hashable {
    case title
    case company
    case location
    case dateRange
    case descriptionText
    case technologies
}

enum ResumeEducationField: String, Codable, Sendable, Hashable {
    case degreeLevel
    case major
    case collegeName
    case expectedGraduation
    case gpa
}

enum ResumeProjectField: String, Codable, Sendable, Hashable {
    case title
    case role
    case technologies
    case summary
    case projectURL
    case dateRange
}

enum ResumeFieldKey: Hashable, Sendable, Codable {
    case personal(ResumePersonalField)
    case summary
    case experience(UUID, ResumeExperienceField)
    case education(UUID, ResumeEducationField)
    case project(UUID, ResumeProjectField)
    case certification(Int)
    case extracurricular(UUID, ResumeExtracurricularField)
    case achievement(UUID, ResumeAchievementField)
    case skillsList

    var storageKey: String {
        switch self {
        case .personal(let field):
            return "personal.\(field.rawValue)"
        case .summary:
            return "summary"
        case .experience(let id, let field):
            return "experience.\(id.uuidString).\(field.rawValue)"
        case .education(let id, let field):
            return "education.\(id.uuidString).\(field.rawValue)"
        case .project(let id, let field):
            return "project.\(id.uuidString).\(field.rawValue)"
        case .certification(let index):
            return "certification.\(index)"
        case .extracurricular(let id, let field):
            return "extracurricular.\(id.uuidString).\(field.rawValue)"
        case .achievement(let id, let field):
            return "achievement.\(id.uuidString).\(field.rawValue)"
        case .skillsList:
            return "skills.list"
        }
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first else { return nil }
        switch head {
        case "personal":
            guard parts.count == 2, let field = ResumePersonalField(rawValue: parts[1]) else { return nil }
            self = .personal(field)
        case "summary":
            self = .summary
        case "experience":
            guard parts.count == 3,
                  let id = UUID(uuidString: parts[1]),
                  let field = ResumeExperienceField(rawValue: parts[2]) else { return nil }
            self = .experience(id, field)
        case "education":
            guard parts.count == 3,
                  let id = UUID(uuidString: parts[1]),
                  let field = ResumeEducationField(rawValue: parts[2]) else { return nil }
            self = .education(id, field)
        case "project":
            guard parts.count == 3,
                  let id = UUID(uuidString: parts[1]),
                  let field = ResumeProjectField(rawValue: parts[2]) else { return nil }
            self = .project(id, field)
        case "certification":
            guard parts.count == 2, let index = Int(parts[1]) else { return nil }
            self = .certification(index)
        case "extracurricular":
            guard parts.count == 3,
                  let id = UUID(uuidString: parts[1]),
                  let field = ResumeExtracurricularField(rawValue: parts[2]) else { return nil }
            self = .extracurricular(id, field)
        case "achievement":
            guard parts.count == 3,
                  let id = UUID(uuidString: parts[1]),
                  let field = ResumeAchievementField(rawValue: parts[2]) else { return nil }
            self = .achievement(id, field)
        case "skills":
            guard parts.count == 2, parts[1] == "list" else { return nil }
            self = .skillsList
        default:
            return nil
        }
    }
}

enum ResumeExtracurricularField: String, Codable, Sendable, Hashable {
    case organization
    case role
    case dateRange
    case descriptionText
}

enum ResumeAchievementField: String, Codable, Sendable, Hashable {
    case name
    case organization
    case dateReceived
    case descriptionText
}

extension Dictionary where Key == ResumeFieldKey, Value == String {
    var storageRepresentation: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in self {
            result[key.storageKey] = value
        }
        return result
    }

    init(storageRepresentation: [String: String]) {
        self = storageRepresentation.reduce(into: [:]) { result, pair in
            guard let key = ResumeFieldKey(storageKey: pair.key) else { return }
            result[key] = pair.value
        }
    }
}
