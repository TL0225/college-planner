// ResumeSectionAliasRegistry.swift
// Feature: Career / ResumeParsing
// Purpose: Map normalized section headers to canonical categories.

import Foundation

enum ResumeSectionCategory: String, Sendable {
    case experience, projects, education, skills, summary, certifications, awards, publications, other
}

enum ResumeSectionAliasRegistry {
    private static let experienceAliases: Set<String> = [
        "work experience", "professional experience", "relevant experience", "employment history",
        "internships", "co-op experience", "leadership experience", "research experience"
    ]
    private static let projectAliases: Set<String> = [
        "projects", "personal projects", "academic projects", "selected projects", "capstone"
    ]
    private static let educationAliases: Set<String> = [
        "education", "academic background", "qualifications"
    ]
    private static let skillsAliases: Set<String> = [
        "skills", "technical skills", "technologies", "programming languages"
    ]
    private static let summaryAliases: Set<String> = [
        "summary", "professional summary", "profile", "career objective"
    ]

    static func normalizeHeader(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func category(forHeader header: String) -> ResumeSectionCategory {
        let key = normalizeHeader(header)
        if experienceAliases.contains(key) { return .experience }
        if projectAliases.contains(key) { return .projects }
        if educationAliases.contains(key) { return .education }
        if skillsAliases.contains(key) { return .skills }
        if summaryAliases.contains(key) { return .summary }
        return .other
    }
}
