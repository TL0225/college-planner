// ResumeSnapshotBuilder.swift
// Feature: Resume
// Purpose: Build ResumeSnapshot from the active Profile on the main actor.

import CryptoKit
import Foundation

@MainActor
enum ResumeSnapshotBuilder {
    static func build(collegePersistence: CollegePersistence = .shared) throws -> ResumeSnapshot {
        guard let profile = ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) else {
            throw ResumeSnapshotBuilderError.noProfile
        }
        return snapshot(from: profile)
    }

    static func snapshot(from profile: Profile) -> ResumeSnapshot {
        let personal = makePersonalInfo(from: profile)
        let education = makeEducation(from: profile)
        let experiences = makeExperiences(from: profile)
        let projects = makeProjects(from: profile)
        let skills = profile.skillsList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let achievements = makeAchievements(from: profile)

        return ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: profile.id,
            capturedAt: Date(),
            profileRevisionToken: revisionToken(
                profile: profile,
                skills: skills,
                projects: profile.portfolioProjectsList
            ),
            personal: personal,
            education: education,
            experiences: experiences,
            projects: projects,
            skills: skills,
            achievements: achievements
        )
    }

    static func currentRevisionToken(
        collegePersistence: CollegePersistence = .shared
    ) -> String? {
        guard let profile = ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) else {
            return nil
        }
        return revisionToken(
            profile: profile,
            skills: profile.skillsList,
            projects: profile.portfolioProjectsList
        )
    }

    // MARK: - Private

    private static func makePersonalInfo(from profile: Profile) -> ResumePersonalInfo {
        let links = classifyLinks(profile.linksList)
        return ResumePersonalInfo(
            name: profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Resume",
            pronouns: trimmedOptional(profile.pronouns),
            email: trimmedOptional(profile.universityEmail),
            phone: trimmedOptional(profile.personalPhone),
            address: trimmedOptional(profile.permanentAddress),
            contactLinks: links
        )
    }

    private static func makeEducation(from profile: Profile) -> [ResumeEducationEntry] {
        let profiles = (profile.academicProfiles ?? [])
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
                return lhs.sortOrder < rhs.sortOrder
            }

        return profiles.compactMap { academic in
            let college = trimmedOptional(academic.collegeName)
            let major = trimmedOptional(academic.major) ?? trimmedOptional(academic.majorsCSV)
            let degree = trimmedOptional(academic.degreeLevel)
            guard college != nil || major != nil || degree != nil else { return nil }

            return ResumeEducationEntry(
                id: academic.id,
                degreeLevel: degree,
                major: major,
                collegeName: college,
                gpa: academic.gpa,
                expectedGraduation: trimmedOptional(academic.expectedGraduation)
                    ?? graduationLabel(from: academic)
            )
        }
    }

    private static func makeExperiences(from profile: Profile) -> [ResumeExperienceEntry] {
        (profile.experiences ?? [])
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .compactMap { experience in
                let title = trimmedOptional(experience.title)
                let company = trimmedOptional(experience.company)
                guard title != nil || company != nil else { return nil }

                return ResumeExperienceEntry(
                    id: experience.id,
                    title: title ?? "Role",
                    company: company ?? "Company",
                    location: trimmedOptional(experience.location),
                    dateRange: ResumeDateFormatting.experienceRange(
                        start: experience.startDate,
                        end: experience.endDate,
                        isCurrent: experience.isCurrent
                    ),
                    descriptionText: trimmedOptional(experience.descriptionText),
                    technologies: trimmedOptional(experience.technologies)
                )
            }
    }

    private static func makeAchievements(from profile: Profile) -> [ResumeAchievementEntry] {
        (profile.achievements ?? []).compactMap { achievement in
            let name = trimmedOptional(achievement.name)
            let organization = trimmedOptional(achievement.organization)
            guard name != nil || organization != nil else { return nil }

            let dateLabel: String?
            if let date = achievement.dateReceived {
                dateLabel = ResumeDateFormatting.monthYear.string(from: date)
            } else {
                dateLabel = nil
            }

            return ResumeAchievementEntry(
                id: achievement.id,
                name: name,
                organization: organization,
                dateReceived: dateLabel,
                descriptionText: trimmedOptional(achievement.descriptionText)
            )
        }
    }

    private static func makeProjects(from profile: Profile) -> [ResumeProjectEntry] {
        profile.portfolioProjectsList.compactMap { project in
            let title = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let bullets = project.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let dateRange: String?
            if let start = project.startDateString?.trimmingCharacters(in: .whitespacesAndNewlines),
               !start.isEmpty {
                let end = project.endDateString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                dateRange = end.isEmpty ? start : "\(start) – \(end)"
            } else {
                dateRange = nil
            }

            return ResumeProjectEntry(
                id: project.id,
                title: title,
                role: trimmedOptional(project.role),
                technologies: trimmedOptional(project.technologies),
                summary: trimmedOptional(project.summary),
                projectURL: trimmedOptional(project.projectURL) ?? trimmedOptional(project.githubURL),
                dateRange: dateRange,
                bullets: bullets
            )
        }
    }

    static func classifyLinks(_ rawLinks: [String]) -> [ResumeContactLink] {
        var linkedIn: ResumeContactLink?
        var github: ResumeContactLink?
        var websites: [ResumeContactLink] = []

        for raw in rawLinks {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()

            if lower.contains("linkedin.com") {
                if linkedIn == nil {
                    linkedIn = ResumeContactLink(kind: .linkedIn, url: trimmed, displayLabel: "LinkedIn")
                }
            } else if lower.contains("github.com") {
                if github == nil {
                    github = ResumeContactLink(kind: .github, url: trimmed, displayLabel: "GitHub")
                }
            } else {
                websites.append(
                    ResumeContactLink(
                        kind: .website,
                        url: trimmed,
                        displayLabel: displayLabel(for: trimmed)
                    )
                )
            }
        }

        var result: [ResumeContactLink] = []
        if let linkedIn { result.append(linkedIn) }
        if let github { result.append(github) }
        result.append(contentsOf: websites.prefix(1))
        return result
    }

    private static func displayLabel(for url: String) -> String {
        guard let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") else {
            return "Website"
        }
        return host
    }

    private static func graduationLabel(from academic: AcademicProfile) -> String? {
        let year = Int(academic.expectedGraduationYear ?? 0)
        let season = academic.expectedGraduationSeason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let season, !season.isEmpty, year > 0 {
            return "\(season) \(year)"
        }
        if year > 0 { return String(year) }
        return nil
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func revisionToken(
        profile: Profile,
        skills: [String],
        projects: [PortfolioProject]
    ) -> String {
        var parts: [String] = [
            profile.id.uuidString,
            profile.name ?? "",
            profile.pronouns ?? "",
            profile.universityEmail ?? "",
            profile.personalPhone ?? "",
            profile.permanentAddress ?? "",
            profile.skillsJSON ?? "",
            profile.linksJSON ?? "",
        ]

        for academic in profile.academicProfiles ?? [] {
            parts.append([
                academic.id.uuidString,
                academic.degreeLevel ?? "",
                academic.major ?? "",
                academic.collegeName ?? "",
                academic.expectedGraduation ?? "",
                academic.gpa.map { String($0) } ?? "",
            ].joined(separator: "|"))
        }

        for experience in profile.experiences ?? [] {
            parts.append([
                experience.id.uuidString,
                experience.title ?? "",
                experience.company ?? "",
                experience.descriptionText ?? "",
            ].joined(separator: "|"))
        }

        for project in projects {
            parts.append([
                project.id.uuidString,
                project.title,
                project.summary,
                project.technologies,
            ].joined(separator: "|"))
        }

        for achievement in profile.achievements ?? [] {
            parts.append([
                achievement.id.uuidString,
                achievement.name ?? "",
                achievement.organization ?? "",
                achievement.descriptionText ?? "",
            ].joined(separator: "|"))
        }

        parts.append(skills.joined(separator: ","))
        let joined = parts.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ResumeSnapshotBuilderError: LocalizedError {
    case noProfile

    var errorDescription: String? {
        switch self {
        case .noProfile:
            return "Add a profile before building a resume."
        }
    }
}

enum ResumeDateFormatting {
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func experienceRange(start: Date?, end: Date?, isCurrent: Bool) -> String {
        let startLabel = start.map { monthYear.string(from: $0) } ?? ""
        let endLabel: String
        if isCurrent {
            endLabel = "Present"
        } else if let end {
            endLabel = monthYear.string(from: end)
        } else {
            endLabel = ""
        }

        switch (startLabel.isEmpty, endLabel.isEmpty) {
        case (true, true): return ""
        case (false, true): return startLabel
        case (true, false): return endLabel
        case (false, false): return "\(startLabel) – \(endLabel)"
        }
    }
}
