// CareerResumeProfileTextAssembler.swift
// Feature: Career
// Purpose: Structured resume profile → plain text for preview and PDF export.

import Foundation

enum CareerResumeProfileTextAssembler {
    static func assemble(_ profile: CareerResumeStructuredProfile) -> String {
        var sections: [String] = []

        var contact: [String] = []
        if let name = profile.name, !name.isEmpty { contact.append(name) }
        if let email = profile.email, !email.isEmpty { contact.append(email) }
        if let phone = profile.phone, !phone.isEmpty { contact.append(phone) }
        if let location = profile.location, !location.isEmpty { contact.append(location) }
        if !contact.isEmpty {
            sections.append("CONTACT\n" + contact.joined(separator: " · "))
        }

        if let summary = profile.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            sections.append("SUMMARY\n\(summary)")
        }

        if !profile.experience.isEmpty {
            var block = "EXPERIENCE"
            for entry in profile.experience {
                block += "\n\n" + entry.headingLines.joined(separator: "\n")
                for bullet in entry.bullets {
                    block += "\n• \(bullet)"
                }
            }
            sections.append(block)
        }

        if !profile.education.isEmpty {
            var block = "EDUCATION"
            for entry in profile.education {
                block += "\n\n" + entry.headingLines.joined(separator: "\n")
                for line in entry.bullets where !line.isEmpty {
                    block += "\n• \(line)"
                }
            }
            sections.append(block)
        }

        if !profile.skills.isEmpty {
            sections.append("SKILLS\n" + profile.skills.joined(separator: " · "))
        }

        if !profile.projects.isEmpty {
            var block = "PROJECTS"
            for entry in profile.projects {
                block += "\n\n" + entry.headingLines.joined(separator: "\n")
                for bullet in entry.bullets {
                    block += "\n• \(bullet)"
                }
            }
            sections.append(block)
        }

        for section in profile.otherSections where !section.lines.isEmpty {
            sections.append("\(section.title.uppercased())\n" + section.lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
