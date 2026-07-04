// ResumeSectionKind.swift
// Feature: Resume
// Purpose: Resume section identifiers with Transferable drag support.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum ResumeSectionKind: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case personal
    case summary
    case education
    case experience
    case projects
    case skills
    case achievements
    case certifications
    case extracurriculars

    var id: String { rawValue }

    /// Sections the user can add/reorder (personal is always anchored).
    static let orderableCases: [ResumeSectionKind] = [
        .summary,
        .education,
        .experience,
        .projects,
        .skills,
        .achievements,
        .certifications,
        .extracurriculars,
    ]

    /// Categories shown in the guided builder sidebar.
    static let guidedCategories: [ResumeSectionKind] = [
        .personal,
        .summary,
        .education,
        .experience,
        .projects,
        .skills,
        .achievements,
        .certifications,
        .extracurriculars,
    ]

    /// Sections tracked by the completion checklist (excludes personal header).
    static let checklistCases: [ResumeSectionKind] = [
        .summary,
        .education,
        .experience,
        .projects,
        .skills,
        .achievements,
        .certifications,
        .extracurriculars,
    ]

    var title: String {
        switch self {
        case .personal: return "Personal Info"
        case .summary: return "Summary"
        case .education: return "Education"
        case .experience: return "Work Experience"
        case .projects: return "Projects"
        case .skills: return "Skills"
        case .achievements: return "Achievements"
        case .certifications: return "Certifications"
        case .extracurriculars: return "Extracurriculars"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "person.crop.circle"
        case .summary: return "text.alignleft"
        case .education: return "graduationcap"
        case .experience: return "briefcase"
        case .projects: return "folder"
        case .skills: return "star"
        case .achievements: return "trophy"
        case .certifications: return "checkmark.seal"
        case .extracurriculars: return "figure.run"
        }
    }

    var emptySectionMessage: String {
        switch self {
        case .personal:
            return "Personal info is empty — add your name in Profile."
        case .summary:
            return "Add a short professional summary to introduce yourself."
        case .education:
            return "Education section is empty — add education in your profile."
        case .experience:
            return "Experience section is empty — add work experience in your profile."
        case .projects:
            return "Projects section is empty — add projects in your profile."
        case .skills:
            return "Skills section is empty — add skills in your profile."
        case .achievements:
            return "Achievements section is empty — add awards in your profile."
        case .certifications:
            return "Add certifications, licenses, or credentials."
        case .extracurriculars:
            return "Add clubs, leadership roles, or volunteer activities."
        }
    }

    var isProfileSourced: Bool {
        switch self {
        case .personal, .education, .experience, .projects, .skills, .achievements:
            return true
        case .summary, .certifications, .extracurriculars:
            return false
        }
    }
}

extension UTType {
    static let resumeSection = UTType(exportedAs: "Timothy.College.resume-section", conformingTo: .data)
}

extension ResumeSectionKind: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .resumeSection)
    }
}
