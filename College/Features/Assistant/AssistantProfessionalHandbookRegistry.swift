// AssistantProfessionalHandbookRegistry.swift
// Feature: Assistant
// Purpose: Assistant module — Entry.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Static map of professional-school contexts to official student handbooks / policy hubs.
/// Out of scope per product plan: scraping these sites — only curated URLs for planner injection.
enum AssistantProfessionalHandbookRegistry {
    struct Entry: Sendable, Equatable {
        let label: String
        let url: String
    }

    /// Best-effort match using strict degree/program tokens first, then secondary college-name hints.
    static func entry(
        collegeName: String?,
        resolvedCollegeFromMajor: String?,
        major: String? = nil,
        minor: String? = nil,
        majorEntityName: String? = nil,
        degreeType: String? = nil
    ) -> Entry? {
        let haystackParts = [
            major,
            minor,
            majorEntityName,
            degreeType,
            collegeName,
            resolvedCollegeFromMajor,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        let haystackLower = haystackParts.joined(separator: " ").lowercased()

        if matchesLawPrimary(haystackLower) || matchesLawSecondary(collegeName: collegeName, resolved: resolvedCollegeFromMajor) {
            return Entry(
                label: "Law school student resources",
                url: "https://www.law.buffalo.edu/student-life/student-resources.html"
            )
        }
        if matchesDentalPrimary(haystackLower) || matchesDentalSecondary(haystackLower) {
            return Entry(
                label: "Dental medicine student handbook",
                url: "https://dental.buffalo.edu/education/academic-programs/student-handbook.html"
            )
        }
        if matchesMedicalPrimary(haystackLower) || matchesMedicalSecondary(haystackLower) {
            return Entry(
                label: "Jacobs School of Medicine student policies",
                url: "https://medicine.buffalo.edu/education/md_degree/md_programs/policies.html"
            )
        }
        return nil
    }

    private static func matchesLawPrimary(_ lower: String) -> Bool {
        if rangeMatches(#"(?i)\b(jd|j\.\s*d\.|juris\s+doctor|doctor\s+of\s+jurisprudence|llm|ll\.m\.)\b"#, in: lower) { return true }
        if rangeMatches(#"(?i)(school\s+of\s+law|faculty\s+of\s+law|law\s+school)"#, in: lower) { return true }
        return false
    }

    private static func matchesLawSecondary(collegeName: String?, resolved: String?) -> Bool {
        let bundle = [collegeName, resolved]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        guard !bundle.isEmpty else { return false }
        return rangeMatches(#"(?i)(school\s+of\s+law|faculty\s+of\s+law|law\s+school)"#, in: bundle)
    }

    private static func matchesDentalPrimary(_ lower: String) -> Bool {
        rangeMatches(#"(?i)\b(dds|dmd)\b"#, in: lower)
            || rangeMatches(#"(?i)\bdental\s+medicine\b"#, in: lower)
            || rangeMatches(#"(?i)\bsd\s*m\b"#, in: lower)
    }

    private static func matchesDentalSecondary(_ lower: String) -> Bool {
        lower.contains("sdm") && rangeMatches(#"(?i)dental"#, in: lower)
    }

    private static func matchesMedicalPrimary(_ lower: String) -> Bool {
        if rangeMatches(#"(?i)\b(jsmbs)\b"#, in: lower) { return true }
        if rangeMatches(#"(?i)(jacobs\s+school|jacobs\s+school\s+of\s+medicine)"#, in: lower) { return true }
        if rangeMatches(#"(?i)\b(md\s+program|md\s+degree|medicine\s+md)\b"#, in: lower) { return true }
        if rangeMatches(#"(?i)\bdoctor\s+of\s+medicine\b"#, in: lower) { return true }
        return false
    }

    private static func matchesMedicalSecondary(_ lower: String) -> Bool {
        (lower.contains("medical") || lower.contains("medicine")) && !matchesDentalPrimary(lower)
    }

    private static func rangeMatches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Short block appended to planner context so the model leads with the official handbook link.
    static func plannerBlock(
        collegeName: String?,
        resolvedCollegeFromMajor: String?,
        major: String? = nil,
        minor: String? = nil,
        majorEntityName: String? = nil,
        degreeType: String? = nil
    ) -> String? {
        guard let entry = entry(
            collegeName: collegeName,
            resolvedCollegeFromMajor: resolvedCollegeFromMajor,
            major: major,
            minor: minor,
            majorEntityName: majorEntityName,
            degreeType: degreeType
        ) else {
            return nil
        }
        return """
Professional handbook (lead with this link before paraphrasing school-specific rules):
- \(entry.label): \(entry.url)
Disclaimer: Not legal advice; confirm degree rules with your school office.
"""
    }
}
