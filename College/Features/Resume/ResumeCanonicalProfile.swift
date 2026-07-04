// ResumeCanonicalProfile.swift
// Feature: Resume
// Purpose: JSON Resume–inspired interchange hub between snapshot, structured parse, and apply.

import Foundation

struct ResumeCanonicalProfile: Codable, Sendable, Equatable, Hashable {
    struct Basics: Codable, Sendable, Equatable, Hashable {
        var name: String?
        var email: String?
        var phone: String?
        var location: String?
        var summary: String?
        var links: [String]
    }

    struct WorkEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
        var id: UUID
        var position: String?
        var company: String?
        var location: String?
        var dateRange: String?
        var highlights: [String]
        var technologies: String?
    }

    struct EducationEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
        var id: UUID
        var institution: String?
        var studyType: String?
        var area: String?
        var gpa: Double?
        var endDate: String?
    }

    struct ProjectEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
        var id: UUID
        var name: String?
        var role: String?
        var description: String?
        var highlights: [String]
        var technologies: String?
        var url: String?
        var dateRange: String?
    }

    struct SkillGroup: Codable, Sendable, Equatable, Hashable {
        var category: String
        var skills: [String]
    }

    var basics: Basics?
    var work: [WorkEntry]
    var education: [EducationEntry]
    var projects: [ProjectEntry]
    var skills: [String]
    var skillGroups: [SkillGroup]
    var certifications: [String]

    init(
        basics: Basics? = nil,
        work: [WorkEntry] = [],
        education: [EducationEntry] = [],
        projects: [ProjectEntry] = [],
        skills: [String] = [],
        skillGroups: [SkillGroup] = [],
        certifications: [String] = []
    ) {
        self.basics = basics
        self.work = work
        self.education = education
        self.projects = projects
        self.skills = skills
        self.skillGroups = skillGroups
        self.certifications = certifications
    }

    var hasContent: Bool {
        if let basics, basics.hasContent { return true }
        if !work.isEmpty || !education.isEmpty || !projects.isEmpty { return true }
        if !skills.isEmpty || !skillGroups.isEmpty || !certifications.isEmpty { return true }
        return false
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> ResumeCanonicalProfile? {
        guard let json,
              let data = json.data(using: .utf8),
              let profile = try? JSONDecoder().decode(ResumeCanonicalProfile.self, from: data)
        else { return nil }
        return profile
    }

    // MARK: - Snapshot

    static func from(snapshot: ResumeSnapshot) -> ResumeCanonicalProfile {
        let personal = snapshot.personal
        let basics = Basics(
            name: trimmed(personal.name),
            email: trimmed(personal.email),
            phone: trimmed(personal.phone),
            location: trimmed(personal.address),
            summary: trimmed(snapshot.summary),
            links: personal.contactLinks.map(\.url)
        )

        return ResumeCanonicalProfile(
            basics: basics.hasContent ? basics : nil,
            work: snapshot.experiences.map { experience in
                WorkEntry(
                    id: experience.id,
                    position: trimmed(experience.title),
                    company: trimmed(experience.company),
                    location: trimmed(experience.location),
                    dateRange: trimmed(experience.dateRange),
                    highlights: bullets(from: experience.descriptionText),
                    technologies: trimmed(experience.technologies)
                )
            },
            education: snapshot.education.map { entry in
                EducationEntry(
                    id: entry.id,
                    institution: trimmed(entry.collegeName),
                    studyType: trimmed(entry.degreeLevel),
                    area: trimmed(entry.major),
                    gpa: entry.gpa,
                    endDate: trimmed(entry.expectedGraduation)
                )
            },
            projects: snapshot.projects.map { entry in
                ProjectEntry(
                    id: entry.id,
                    name: trimmed(entry.title),
                    role: trimmed(entry.role),
                    description: trimmed(entry.summary),
                    highlights: entry.bullets,
                    technologies: trimmed(entry.technologies),
                    url: trimmed(entry.projectURL),
                    dateRange: trimmed(entry.dateRange)
                )
            },
            skills: snapshot.skills,
            skillGroups: [],
            certifications: snapshot.certifications
        )
    }

    @MainActor
    func toSnapshot(
        sourceProfileID: UUID,
        profileRevisionToken: String,
        capturedAt: Date = Date()
    ) -> ResumeSnapshot {
        let basics = self.basics ?? Basics(
            name: nil,
            email: nil,
            phone: nil,
            location: nil,
            summary: nil,
            links: []
        )
        let links = ResumeSnapshotBuilder.classifyLinks(basics.links)

        return ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: sourceProfileID,
            capturedAt: capturedAt,
            profileRevisionToken: profileRevisionToken,
            personal: ResumePersonalInfo(
                name: basics.name ?? "Resume",
                pronouns: nil,
                email: basics.email,
                phone: basics.phone,
                address: basics.location,
                contactLinks: links
            ),
            summary: basics.summary,
            education: education.map { entry in
                ResumeEducationEntry(
                    id: entry.id,
                    degreeLevel: entry.studyType,
                    major: entry.area,
                    collegeName: entry.institution,
                    gpa: entry.gpa,
                    expectedGraduation: entry.endDate
                )
            },
            experiences: work.map { entry in
                ResumeExperienceEntry(
                    id: entry.id,
                    title: entry.position ?? "Role",
                    company: entry.company ?? "Company",
                    location: entry.location,
                    dateRange: entry.dateRange ?? "",
                    descriptionText: Self.joinedBullets(entry.highlights),
                    technologies: entry.technologies
                )
            },
            projects: projects.map { entry in
                ResumeProjectEntry(
                    id: entry.id,
                    title: entry.name ?? "Project",
                    role: entry.role,
                    technologies: entry.technologies,
                    summary: entry.description,
                    projectURL: entry.url,
                    dateRange: entry.dateRange,
                    bullets: entry.highlights
                )
            },
            skills: skills,
            achievements: [],
            certifications: certifications,
            extracurriculars: []
        )
    }

    // MARK: - Structured parse profile

    static func from(structured: CareerResumeStructuredProfile) -> ResumeCanonicalProfile {
        ResumeCanonicalProfile(
            basics: Basics(
                name: trimmed(structured.name),
                email: trimmed(structured.email),
                phone: trimmed(structured.phone),
                location: trimmed(structured.location),
                summary: trimmed(structured.summary),
                links: structured.links
            ).nonEmpty,
            work: structured.experience.map { workEntry(from: $0) },
            education: structured.education.map { educationEntry(from: $0) },
            projects: structured.projects.map { projectEntry(from: $0) },
            skills: structured.skills,
            skillGroups: structured.skillGroups.map {
                SkillGroup(category: $0.category, skills: $0.skills)
            },
            certifications: structured.certifications
        )
    }

    func toStructuredProfile() -> CareerResumeStructuredProfile {
        let basics = self.basics
        return CareerResumeStructuredProfile(
            name: basics?.name,
            email: basics?.email,
            phone: basics?.phone,
            location: basics?.location,
            links: basics?.links ?? [],
            summary: basics?.summary,
            skills: skills,
            skillGroups: skillGroups.map {
                CareerResumeStructuredProfile.SkillGroup(category: $0.category, skills: $0.skills)
            },
            education: education.map { structuredEducationEntry(from: $0) },
            experience: work.map { structuredWorkEntry(from: $0) },
            projects: projects.map { structuredProjectEntry(from: $0) },
            certifications: certifications,
            otherSections: []
        )
    }

    // MARK: - Private

    private static func workEntry(from entry: CareerResumeStructuredProfile.Entry) -> WorkEntry {
        let headings = entry.headingLines
        return WorkEntry(
            id: UUID(),
            position: headings.first.flatMap(trimmed),
            company: headings.dropFirst().first.flatMap(trimmed),
            location: headings.dropFirst(2).first.flatMap(trimmed),
            dateRange: headings.last.flatMap(trimmed),
            highlights: entry.bullets,
            technologies: nil
        )
    }

    private static func educationEntry(from entry: CareerResumeStructuredProfile.Entry) -> EducationEntry {
        let headings = entry.headingLines
        return EducationEntry(
            id: UUID(),
            institution: headings.dropFirst().first.flatMap(trimmed) ?? headings.first.flatMap(trimmed),
            studyType: headings.first.flatMap(trimmed),
            area: headings.dropFirst().first.flatMap(trimmed),
            gpa: nil,
            endDate: headings.last.flatMap(trimmed)
        )
    }

    private static func projectEntry(from entry: CareerResumeStructuredProfile.Entry) -> ProjectEntry {
        ProjectEntry(
            id: UUID(),
            name: entry.headingLines.first.flatMap(trimmed),
            role: entry.headingLines.dropFirst().first.flatMap(trimmed),
            description: entry.bullets.first.flatMap(trimmed),
            highlights: Array(entry.bullets.dropFirst()),
            technologies: nil,
            url: nil,
            dateRange: entry.headingLines.last.flatMap(trimmed)
        )
    }

    private func structuredWorkEntry(from entry: WorkEntry) -> CareerResumeStructuredProfile.Entry {
        var headingLines: [String] = []
        if let position = Self.trimmed(entry.position) { headingLines.append(position) }
        if let company = Self.trimmed(entry.company) { headingLines.append(company) }
        if let location = Self.trimmed(entry.location) { headingLines.append(location) }
        if let dateRange = Self.trimmed(entry.dateRange) { headingLines.append(dateRange) }
        return CareerResumeStructuredProfile.Entry(
            headingLines: headingLines,
            bullets: entry.highlights
        )
    }

    private func structuredEducationEntry(from entry: EducationEntry) -> CareerResumeStructuredProfile.Entry {
        var headingLines: [String] = []
        if let studyType = Self.trimmed(entry.studyType) { headingLines.append(studyType) }
        if let area = Self.trimmed(entry.area) { headingLines.append(area) }
        if let institution = Self.trimmed(entry.institution) { headingLines.append(institution) }
        if let endDate = Self.trimmed(entry.endDate) { headingLines.append(endDate) }
        if let gpa = entry.gpa {
            headingLines.append("GPA: \(String(format: "%.2f", gpa))")
        }
        return CareerResumeStructuredProfile.Entry(headingLines: headingLines, bullets: [])
    }

    private func structuredProjectEntry(from entry: ProjectEntry) -> CareerResumeStructuredProfile.Entry {
        var headingLines: [String] = []
        if let name = Self.trimmed(entry.name) { headingLines.append(name) }
        if let role = Self.trimmed(entry.role) { headingLines.append(role) }
        if let dateRange = Self.trimmed(entry.dateRange) { headingLines.append(dateRange) }
        var bullets = entry.highlights
        if let description = Self.trimmed(entry.description) {
            bullets.insert(description, at: 0)
        }
        return CareerResumeStructuredProfile.Entry(headingLines: headingLines, bullets: bullets)
    }

    private static func bullets(from descriptionText: String?) -> [String] {
        guard let descriptionText else { return [] }
        return descriptionText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func joinedBullets(_ bullets: [String]) -> String? {
        let trimmedBullets = bullets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedBullets.isEmpty else { return nil }
        return trimmedBullets.joined(separator: "\n")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ResumeCanonicalProfile.Basics {
    var hasContent: Bool {
        name != nil || email != nil || phone != nil || location != nil || summary != nil || !links.isEmpty
    }

    var nonEmpty: ResumeCanonicalProfile.Basics? {
        hasContent ? self : nil
    }
}
