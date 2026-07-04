// ResumeTemplate.swift
// Feature: Resume
// Purpose: Typst template abstraction and Standard ATS template.

import Foundation

protocol ResumeTemplate: Sendable {
    static var identifier: String { get }
    func makeTypstSource(_ model: ResumeRenderModel) -> String
}

enum TypstEscaping {
    static func escape(_ field: String) -> String {
        var result = ""
        result.reserveCapacity(field.count)
        for scalar in field.unicodeScalars {
            switch Character(scalar) {
            case "#": result += "\\#"
            case "*": result += "\\*"
            case "_": result += "\\_"
            case "@": result += "\\@"
            case "\\": result += "\\\\"
            case "[": result += "\\["
            case "]": result += "\\]"
            case "$": result += "\\$"
            case "<": result += "\\<"
            case ">": result += "\\>"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

struct StandardATSTemplate: ResumeTemplate {
    static let identifier = "standard-ats-v1"

    func makeTypstSource(_ model: ResumeRenderModel) -> String {
        let style = model.style
        var lines: [String] = []

        let pageWidth = style.pageSize == .a4 ? "210mm" : "8.5in"
        let pageHeight = style.pageSize == .a4 ? "297mm" : "11in"
        let margin = String(format: "%.2fin", style.marginInches)

        lines.append("#set page(width: \(pageWidth), height: \(pageHeight), margin: (x: \(margin), y: \(margin)))")
        lines.append("#set text(font: \"\(style.fontFamily)\", size: \(style.bodySize)pt)")
        lines.append("#set par(justify: false, leading: \(style.lineLeading)em)")
        lines.append("")

        appendPersonal(&lines, model.personal, headingScale: style.headingScale)

        for section in model.orderedSections {
            switch section {
            case .personal:
                continue
            case .summary(let rendered):
                appendSummary(&lines, rendered)
            case .education(let rendered):
                appendEducation(&lines, rendered)
            case .experience(let rendered):
                appendExperience(&lines, rendered)
            case .projects(let rendered):
                appendProjects(&lines, rendered)
            case .skills(let rendered):
                appendSkills(&lines, rendered)
            case .achievements(let rendered):
                appendAchievements(&lines, rendered)
            case .certifications(let rendered):
                appendCertifications(&lines, rendered)
            case .extracurriculars(let rendered):
                appendExtracurriculars(&lines, rendered)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private func appendPersonal(
        _ lines: inout [String],
        _ personal: RenderedPersonalSection,
        headingScale: Double
    ) {
        let name = TypstEscaping.escape(personal.name)
        if let pronouns = personal.pronouns {
            lines.append("= \(name) #text(size: 9pt, fill: gray)[(\(TypstEscaping.escape(pronouns)))]")
        } else {
            lines.append("= \(name)")
        }

        if !personal.contactLine.isEmpty {
            lines.append("#text(size: 9.5pt)[\(TypstEscaping.escape(personal.contactLine))]")
        }

        for link in personal.contactLinks {
            let label = TypstEscaping.escape(link.displayLabel)
            let url = TypstEscaping.escape(link.url)
            lines.append("#link(\"\(url)\")[#text(size: 9pt)[\(label)]]")
        }
        lines.append("")
        _ = headingScale
    }

    private func appendSummary(_ lines: inout [String], _ section: RenderedSummarySection) {
        lines.append("== Professional Summary")
        lines.append(TypstEscaping.escape(section.text))
        lines.append("")
    }

    private func appendEducation(_ lines: inout [String], _ section: RenderedEducationSection) {
        lines.append("== Education")
        for entry in section.entries {
            var headline: [String] = []
            if let degree = entry.degreeLevel { headline.append(TypstEscaping.escape(degree)) }
            if let major = entry.major { headline.append(TypstEscaping.escape(major)) }
            if !headline.isEmpty {
                lines.append("*\(headline.joined(separator: ", "))*")
            }
            var sub: [String] = []
            if let college = entry.collegeName { sub.append(TypstEscaping.escape(college)) }
            if let grad = entry.expectedGraduation { sub.append(TypstEscaping.escape(grad)) }
            if !sub.isEmpty {
                lines.append(sub.joined(separator: " · "))
            }
            if let gpa = entry.gpa {
                lines.append("GPA: \(String(format: "%.2f", gpa))")
            }
            lines.append("")
        }
    }

    private func appendExperience(_ lines: inout [String], _ section: RenderedExperienceSection) {
        lines.append("== Work Experience")
        for entry in section.entries {
            lines.append("*\(TypstEscaping.escape(entry.title))* at \(TypstEscaping.escape(entry.company))")
            var meta: [String] = []
            if !entry.dateRange.isEmpty { meta.append(TypstEscaping.escape(entry.dateRange)) }
            if let location = entry.location { meta.append(TypstEscaping.escape(location)) }
            if !meta.isEmpty {
                lines.append("#text(size: 9pt, fill: gray)[\(meta.joined(separator: " · "))]")
            }
            if let description = entry.descriptionText {
                for paragraph in description.components(separatedBy: "\n") {
                    let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    lines.append("- \(TypstEscaping.escape(trimmed))")
                }
            }
            if let technologies = entry.technologies {
                lines.append("#text(size: 9pt)[Technologies: \(TypstEscaping.escape(technologies))]")
            }
            lines.append("")
        }
    }

    private func appendProjects(_ lines: inout [String], _ section: RenderedProjectsSection) {
        lines.append("== Projects")
        for entry in section.entries {
            lines.append("*\(TypstEscaping.escape(entry.title))*")
            var meta: [String] = []
            if let role = entry.role { meta.append(TypstEscaping.escape(role)) }
            if let dateRange = entry.dateRange { meta.append(TypstEscaping.escape(dateRange)) }
            if !meta.isEmpty {
                lines.append("#text(size: 9pt, fill: gray)[\(meta.joined(separator: " · "))]")
            }
            if let summary = entry.summary {
                lines.append(TypstEscaping.escape(summary))
            }
            for bullet in entry.bullets {
                lines.append("- \(TypstEscaping.escape(bullet))")
            }
            if let url = entry.projectURL {
                lines.append("#link(\"\(TypstEscaping.escape(url))\")")
            }
            lines.append("")
        }
    }

    private func appendSkills(_ lines: inout [String], _ section: RenderedSkillsSection) {
        lines.append("== Skills")
        lines.append(section.skills.map { TypstEscaping.escape($0) }.joined(separator: " · "))
        lines.append("")
    }

    private func appendAchievements(_ lines: inout [String], _ section: RenderedAchievementsSection) {
        lines.append("== Awards")
        for entry in section.entries {
            var headline: [String] = []
            if let name = entry.name { headline.append(TypstEscaping.escape(name)) }
            if let organization = entry.organization { headline.append(TypstEscaping.escape(organization)) }
            if !headline.isEmpty {
                lines.append("*\(headline.joined(separator: " · "))*")
            }
            if let date = entry.dateReceived {
                lines.append("#text(size: 9pt, fill: gray)[\(TypstEscaping.escape(date))]")
            }
            if let description = entry.descriptionText {
                lines.append(TypstEscaping.escape(description))
            }
            lines.append("")
        }
    }

    private func appendCertifications(_ lines: inout [String], _ section: RenderedCertificationsSection) {
        lines.append("== Certifications")
        for item in section.items {
            lines.append("- \(TypstEscaping.escape(item))")
        }
        lines.append("")
    }

    private func appendExtracurriculars(_ lines: inout [String], _ section: RenderedExtracurricularsSection) {
        lines.append("== Activities")
        for entry in section.entries {
            var headline = TypstEscaping.escape(entry.organization)
            if let role = entry.role {
                headline += " — \(TypstEscaping.escape(role))"
            }
            lines.append("*\(headline)*")
            if let dateRange = entry.dateRange {
                lines.append("#text(size: 9pt, fill: gray)[\(TypstEscaping.escape(dateRange))]")
            }
            if let description = entry.descriptionText {
                lines.append(TypstEscaping.escape(description))
            }
            lines.append("")
        }
    }
}
