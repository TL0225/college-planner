// AssistantProgramIdentityBuilder.swift
// Feature: Assistant
// Purpose: Resolve declared program to catalog identity (Ship B).

import Foundation

enum AssistantProgramDisambiguationStatus: String, Codable, Sendable {
    case resolved
    case ambiguous
    case missing
}

struct AssistantProgramIdentityContext: Sendable, Equatable {
    var majorDisplayName: String
    var resolvedCollege: String?
    var resolvedDepartment: String?
    var programURL: String?
    var degreeType: String?
    var disambiguationStatus: AssistantProgramDisambiguationStatus
    var ambiguousCandidates: [String]
}

enum AssistantProgramIdentityBuilder {
    @MainActor
    static func build(persistence: CollegePersistence) -> AssistantProgramIdentityContext {
        let majors = persistence.resolvedMajorNames()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primary = majors.first ?? ""
        let degreeType = persistence.primaryDegreeType()
        let programURL = persistence.resolveSelectedMajorProgramURL()

        if primary.isEmpty {
            return AssistantProgramIdentityContext(
                majorDisplayName: "",
                resolvedCollege: nil,
                resolvedDepartment: nil,
                programURL: nil,
                degreeType: degreeType,
                disambiguationStatus: .missing,
                ambiguousCandidates: []
            )
        }

        let metadata = persistence.activeSchoolPolicyMetadata()
        let _ = metadata?.catalogURL

        return AssistantProgramIdentityContext(
            majorDisplayName: primary,
            resolvedCollege: nil,
            resolvedDepartment: nil,
            programURL: programURL,
            degreeType: degreeType,
            disambiguationStatus: programURL == nil ? .ambiguous : .resolved,
            ambiguousCandidates: programURL == nil ? majors : []
        )
    }

    static func disclaimerLine(for identity: AssistantProgramIdentityContext) -> String? {
        guard identity.disambiguationStatus == .ambiguous else { return nil }
        return "_If your program differs (e.g. another school or degree type), requirements may vary — confirm in Profile._"
    }

    static func promptBlock(for identity: AssistantProgramIdentityContext) -> String {
        var lines: [String] = ["Declared program identity:"]
        if identity.majorDisplayName.isEmpty {
            lines.append("- major: (none selected)")
        } else {
            lines.append("- major: \(identity.majorDisplayName)")
        }
        if let college = identity.resolvedCollege {
            lines.append("- college/school: \(college)")
        }
        if let url = identity.programURL {
            lines.append("- programURL: \(url)")
        }
        if let degree = identity.degreeType {
            lines.append("- degreeType: \(degree)")
        }
        lines.append("- disambiguation: \(identity.disambiguationStatus.rawValue)")
        return lines.joined(separator: "\n")
    }
}
