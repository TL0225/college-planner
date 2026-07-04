// CareerResumeStructuredParserV2.swift
// Feature: Career / ResumeParsing
// Purpose: Typed parser V2 built on alias registry + heading parser.

import Foundation

enum CareerResumeStructuredParserV2 {
    static func parse(plainText: String) -> ParsedResumeDocument {
        let lines = plainText.components(separatedBy: .newlines)
        var currentHeader: String?
        var sections: [String: [String]] = [:]
        var sectionOrder: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isLikelyHeader(trimmed) {
                currentHeader = trimmed
                if sections[currentHeader!] == nil {
                    sectionOrder.append(trimmed)
                    sections[trimmed] = []
                }
                continue
            }
            if let header = currentHeader {
                sections[header, default: []].append(trimmed)
            }
        }

        var experiences: [ParsedExperience] = []
        var projects: [ParsedProject] = []
        var education: [ParsedEducation] = []

        for header in sectionOrder {
            let category = ResumeSectionAliasRegistry.category(forHeader: header)
            let body = sections[header] ?? []
            switch category {
            case .experience:
                experiences.append(contentsOf: mapExperienceLines(body, sectionHeader: header))
            case .projects:
                projects.append(contentsOf: mapProjectLines(body))
            case .education:
                if let entry = mapEducationLines(body) { education.append(entry) }
            default:
                break
            }
        }

        return ParsedResumeDocument(
            personalName: lines.first?.trimmingCharacters(in: .whitespaces),
            email: extractEmail(plainText),
            phone: extractPhone(plainText),
            summary: nil,
            experiences: experiences,
            projects: projects,
            education: education,
            skills: [],
            format: ResumeFormatDetector.detect(plainText: plainText, sections: sectionOrder)
        )
    }

    private static func isLikelyHeader(_ line: String) -> Bool {
        line.count < 48 && line == line.uppercased() && line.contains(where: { $0.isLetter })
    }

    private static func mapExperienceLines(_ lines: [String], sectionHeader: String) -> [ParsedExperience] {
        var entries: [ParsedExperience] = []
        var heading: String?
        var bullets: [String] = []
        func flush() {
            guard let heading else { return }
            let parsed = ResumeHeadingParser.parseExperienceHeading(heading)
            guard !parsed.title.isEmpty else { return }
            entries.append(
                ParsedExperience(
                    id: UUID(),
                    title: parsed.title,
                    company: parsed.company.isEmpty ? "Unknown" : parsed.company,
                    location: parsed.location,
                    employmentType: ResumeHeadingParser.inferEmploymentType(title: parsed.title, sectionHeader: sectionHeader),
                    startDate: nil,
                    endDate: nil,
                    isCurrent: heading.localizedCaseInsensitiveContains("present"),
                    bullets: bullets
                )
            )
            bullets = []
        }
        for line in lines {
            if line.hasPrefix("•") || line.hasPrefix("-") {
                bullets.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else {
                flush()
                heading = line
            }
        }
        flush()
        return entries
    }

    private static func mapProjectLines(_ lines: [String]) -> [ParsedProject] {
        guard let title = lines.first else { return [] }
        return [
            ParsedProject(
                id: UUID(),
                title: title,
                role: lines.dropFirst().first,
                bullets: lines.dropFirst(2).map { $0.trimmingCharacters(in: .whitespaces) }
            )
        ]
    }

    private static func mapEducationLines(_ lines: [String]) -> ParsedEducation? {
        guard let first = lines.first else { return nil }
        return ParsedEducation(id: UUID(), institution: first, degree: lines.dropFirst().first, major: nil)
    }

    private static func extractEmail(_ text: String) -> String? {
        text.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive])
            .map { String(text[$0]) }
    }

    private static func extractPhone(_ text: String) -> String? {
        text.range(of: #"\+?\d[\d\s().-]{7,}\d"#, options: .regularExpression)
            .map { String(text[$0]) }
    }
}
