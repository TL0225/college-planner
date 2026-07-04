// ResumeDocumentCompiler.swift
// Feature: Resume
// Purpose: Merge ResumeDocument overrides into render-ready models and Typst source.

import Foundation

enum ResumeDocumentCompiler {
    static func mergedSnapshot(from document: ResumeDocument) -> ResumeSnapshot {
        var snapshot = document.baseSnapshot
        let overrides = document.fieldOverrides

        if let summary = overrides[ResumeFieldKey.summary.storageKey] {
            snapshot.summary = summary
        }

        snapshot.personal = mergedPersonal(snapshot.personal, overrides: overrides)
        snapshot.education = mergedEducation(snapshot.education, overrides: overrides)
        snapshot.experiences = mergedExperiences(snapshot.experiences, overrides: overrides)
        snapshot.projects = mergedProjects(snapshot.projects, overrides: overrides)
        snapshot.achievements = mergedAchievements(snapshot.achievements, overrides: overrides)
        snapshot.certifications = mergedCertifications(snapshot.certifications, overrides: overrides)
        snapshot.extracurriculars = mergedExtracurriculars(snapshot.extracurriculars, overrides: overrides)
        snapshot.skills = mergedSkills(snapshot.skills, overrides: overrides)

        return snapshot
    }

    static func renderModel(from document: ResumeDocument) -> ResumeRenderModel {
        let snapshot = mergedSnapshot(from: document)
        let includedOrder = document.sectionOrder.filter { document.isSectionIncluded($0) }
        return ResumeRenderModel.make(
            snapshot: snapshot,
            orderedKinds: includedOrder,
            templateID: document.templateID,
            style: document.style
        )
    }

    static func typstSource(from document: ResumeDocument, template: some ResumeTemplate = StandardATSTemplate()) -> String {
        switch document.typstSourceMode {
        case .manual:
            return document.manualTypstSource ?? ""
        case .generated:
            return template.makeTypstSource(renderModel(from: document))
        }
    }

    // MARK: - Private merge helpers

    private static func mergedPersonal(
        _ personal: ResumePersonalInfo,
        overrides: [String: String]
    ) -> ResumePersonalInfo {
        var merged = personal
        for field in ResumePersonalField.allCases {
            let key = ResumeFieldKey.personal(field).storageKey
            guard let value = overrides[key] else { continue }
            switch field {
            case .name: merged.name = value
            case .pronouns: merged.pronouns = value
            case .email: merged.email = value
            case .phone: merged.phone = value
            case .address: merged.address = value
            }
        }
        return merged
    }

    private static func mergedEducation(
        _ entries: [ResumeEducationEntry],
        overrides: [String: String]
    ) -> [ResumeEducationEntry] {
        entries.map { entry in
            var merged = entry
            for field in ResumeEducationField.allCases {
                let key = ResumeFieldKey.education(entry.id, field).storageKey
                guard let value = overrides[key] else { continue }
                switch field {
                case .degreeLevel: merged.degreeLevel = value
                case .major: merged.major = value
                case .collegeName: merged.collegeName = value
                case .expectedGraduation: merged.expectedGraduation = value
                case .gpa: merged.gpa = Double(value)
                }
            }
            return merged
        }
    }

    private static func mergedExperiences(
        _ entries: [ResumeExperienceEntry],
        overrides: [String: String]
    ) -> [ResumeExperienceEntry] {
        entries.map { entry in
            var merged = entry
            for field in ResumeExperienceField.allCases {
                let key = ResumeFieldKey.experience(entry.id, field).storageKey
                guard let value = overrides[key] else { continue }
                switch field {
                case .title: merged.title = value
                case .company: merged.company = value
                case .location: merged.location = value
                case .dateRange: merged.dateRange = value
                case .descriptionText: merged.descriptionText = value
                case .technologies: merged.technologies = value
                }
            }
            return merged
        }
    }

    private static func mergedProjects(
        _ entries: [ResumeProjectEntry],
        overrides: [String: String]
    ) -> [ResumeProjectEntry] {
        entries.map { entry in
            var merged = entry
            for field in ResumeProjectField.allCases {
                let key = ResumeFieldKey.project(entry.id, field).storageKey
                guard let value = overrides[key] else { continue }
                switch field {
                case .title: merged.title = value
                case .role: merged.role = value
                case .technologies: merged.technologies = value
                case .summary: merged.summary = value
                case .projectURL: merged.projectURL = value
                case .dateRange: merged.dateRange = value
                }
            }
            return merged
        }
    }

    private static func mergedAchievements(
        _ entries: [ResumeAchievementEntry],
        overrides: [String: String]
    ) -> [ResumeAchievementEntry] {
        entries.map { entry in
            var merged = entry
            for field in ResumeAchievementField.allCases {
                let key = ResumeFieldKey.achievement(entry.id, field).storageKey
                guard let value = overrides[key] else { continue }
                switch field {
                case .name: merged.name = value
                case .organization: merged.organization = value
                case .dateReceived: merged.dateReceived = value
                case .descriptionText: merged.descriptionText = value
                }
            }
            return merged
        }
    }

    private static func mergedCertifications(
        _ entries: [String],
        overrides: [String: String]
    ) -> [String] {
        guard !overrides.keys.contains(where: { $0.hasPrefix("certification.") }) else {
            let indexed = overrides
                .filter { $0.key.hasPrefix("certification.") }
                .compactMap { key, value -> (Int, String)? in
                    guard let index = Int(key.replacingOccurrences(of: "certification.", with: "")) else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return (index, trimmed)
                }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
            return indexed.isEmpty ? entries : indexed
        }
        return entries
    }

    private static func mergedSkills(
        _ skills: [String],
        overrides: [String: String]
    ) -> [String] {
        guard let joined = overrides[ResumeFieldKey.skillsList.storageKey] else {
            return skills
        }
        return joined
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func mergedExtracurriculars(
        _ entries: [ResumeExtracurricularEntry],
        overrides: [String: String]
    ) -> [ResumeExtracurricularEntry] {
        entries.map { entry in
            var merged = entry
            for field in ResumeExtracurricularField.allCases {
                let key = ResumeFieldKey.extracurricular(entry.id, field).storageKey
                guard let value = overrides[key] else { continue }
                switch field {
                case .organization: merged.organization = value
                case .role: merged.role = value
                case .dateRange: merged.dateRange = value
                case .descriptionText: merged.descriptionText = value
                }
            }
            return merged
        }
    }
}

private extension ResumeEducationField {
    static var allCases: [ResumeEducationField] {
        [.degreeLevel, .major, .collegeName, .expectedGraduation, .gpa]
    }
}

private extension ResumeExperienceField {
    static var allCases: [ResumeExperienceField] {
        [.title, .company, .location, .dateRange, .descriptionText, .technologies]
    }
}

private extension ResumeProjectField {
    static var allCases: [ResumeProjectField] {
        [.title, .role, .technologies, .summary, .projectURL, .dateRange]
    }
}

private extension ResumeAchievementField {
    static var allCases: [ResumeAchievementField] {
        [.name, .organization, .dateReceived, .descriptionText]
    }
}

private extension ResumeExtracurricularField {
    static var allCases: [ResumeExtracurricularField] {
        [.organization, .role, .dateRange, .descriptionText]
    }
}
