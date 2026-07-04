// ResumeRenderModel.swift
// Feature: Resume
// Purpose: Presentation-ready resume data between snapshot capture and template emission.

import Foundation

struct RenderedPersonalSection: Sendable, Hashable, Equatable {
    var name: String
    var pronouns: String?
    var contactLine: String
    var contactLinks: [ResumeContactLink]
}

struct RenderedSummarySection: Sendable, Hashable, Equatable {
    var text: String
}

struct RenderedEducationSection: Sendable, Hashable, Equatable {
    var entries: [ResumeEducationEntry]
}

struct RenderedExperienceSection: Sendable, Hashable, Equatable {
    var entries: [ResumeExperienceEntry]
}

struct RenderedProjectsSection: Sendable, Hashable, Equatable {
    var entries: [ResumeProjectEntry]
}

struct RenderedSkillsSection: Sendable, Hashable, Equatable {
    var skills: [String]
}

struct RenderedAchievementsSection: Sendable, Hashable, Equatable {
    var entries: [ResumeAchievementEntry]
}

struct RenderedCertificationsSection: Sendable, Hashable, Equatable {
    var items: [String]
}

struct RenderedExtracurricularsSection: Sendable, Hashable, Equatable {
    var entries: [ResumeExtracurricularEntry]
}

enum RenderedResumeSection: Sendable, Hashable, Equatable {
    case personal(RenderedPersonalSection)
    case summary(RenderedSummarySection)
    case education(RenderedEducationSection)
    case experience(RenderedExperienceSection)
    case projects(RenderedProjectsSection)
    case skills(RenderedSkillsSection)
    case achievements(RenderedAchievementsSection)
    case certifications(RenderedCertificationsSection)
    case extracurriculars(RenderedExtracurricularsSection)

    var kind: ResumeSectionKind {
        switch self {
        case .personal: return .personal
        case .summary: return .summary
        case .education: return .education
        case .experience: return .experience
        case .projects: return .projects
        case .skills: return .skills
        case .achievements: return .achievements
        case .certifications: return .certifications
        case .extracurriculars: return .extracurriculars
        }
    }
}

struct ResumeRenderModel: Sendable, Hashable, Equatable {
    var snapshotID: UUID
    var sourceProfileID: UUID
    var templateID: String
    var style: ResumeDocumentStyle
    var personal: RenderedPersonalSection
    var orderedSections: [RenderedResumeSection]
    var includedEmptySectionKinds: [ResumeSectionKind]

    static func make(
        snapshot: ResumeSnapshot,
        orderedKinds: [ResumeSectionKind],
        templateID: String = StandardATSTemplate.identifier,
        style: ResumeDocumentStyle = .standard
    ) -> ResumeRenderModel {
        let personal = renderPersonal(snapshot.personal)
        let deduped = deduplicatedOrder(orderedKinds)

        var sections: [RenderedResumeSection] = []
        var emptyIncluded: [ResumeSectionKind] = []

        for kind in deduped where kind != .personal {
            switch kind {
            case .personal:
                continue
            case .summary:
                let text = trimmed(snapshot.summary) ?? ""
                if text.isEmpty {
                    emptyIncluded.append(.summary)
                } else {
                    sections.append(.summary(RenderedSummarySection(text: text)))
                }
            case .education:
                let entries = snapshot.education
                if entries.isEmpty {
                    emptyIncluded.append(.education)
                } else {
                    sections.append(.education(RenderedEducationSection(entries: entries)))
                }
            case .experience:
                let entries = snapshot.experiences
                if entries.isEmpty {
                    emptyIncluded.append(.experience)
                } else {
                    sections.append(.experience(RenderedExperienceSection(entries: entries)))
                }
            case .projects:
                let entries = snapshot.projects
                if entries.isEmpty {
                    emptyIncluded.append(.projects)
                } else {
                    sections.append(.projects(RenderedProjectsSection(entries: entries)))
                }
            case .skills:
                let skills = snapshot.skills
                if skills.isEmpty {
                    emptyIncluded.append(.skills)
                } else {
                    sections.append(.skills(RenderedSkillsSection(skills: skills)))
                }
            case .achievements:
                let entries = snapshot.achievements
                if entries.isEmpty {
                    emptyIncluded.append(.achievements)
                } else {
                    sections.append(.achievements(RenderedAchievementsSection(entries: entries)))
                }
            case .certifications:
                let items = snapshot.certifications
                if items.isEmpty {
                    emptyIncluded.append(.certifications)
                } else {
                    sections.append(.certifications(RenderedCertificationsSection(items: items)))
                }
            case .extracurriculars:
                let entries = snapshot.extracurriculars
                if entries.isEmpty {
                    emptyIncluded.append(.extracurriculars)
                } else {
                    sections.append(.extracurriculars(RenderedExtracurricularsSection(entries: entries)))
                }
            }
        }

        return ResumeRenderModel(
            snapshotID: snapshot.snapshotID,
            sourceProfileID: snapshot.sourceProfileID,
            templateID: templateID,
            style: style,
            personal: personal,
            orderedSections: sections,
            includedEmptySectionKinds: emptyIncluded
        )
    }

    static func make(document: ResumeDocument) -> ResumeRenderModel {
        ResumeDocumentCompiler.renderModel(from: document)
    }

    // MARK: - Private

    private static func deduplicatedOrder(_ kinds: [ResumeSectionKind]) -> [ResumeSectionKind] {
        var seen = Set<ResumeSectionKind>()
        var result: [ResumeSectionKind] = []
        for kind in kinds where kind != .personal {
            guard !seen.contains(kind) else { continue }
            seen.insert(kind)
            result.append(kind)
        }
        return result
    }

    private static func renderPersonal(_ info: ResumePersonalInfo) -> RenderedPersonalSection {
        var contactParts: [String] = []
        if let email = trimmed(info.email) { contactParts.append(email) }
        if let phone = trimmed(info.phone) { contactParts.append(phone) }
        if let address = trimmed(info.address) { contactParts.append(address) }

        for link in info.contactLinks {
            contactParts.append(link.displayLabel)
        }

        return RenderedPersonalSection(
            name: trimmed(info.name) ?? "Resume",
            pronouns: trimmed(info.pronouns),
            contactLine: contactParts.joined(separator: " · "),
            contactLinks: info.contactLinks
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
