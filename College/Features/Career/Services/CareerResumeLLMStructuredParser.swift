// CareerResumeLLMStructuredParser.swift
// Feature: Career / ResumeParsing
// Purpose: Jobright-style staged extraction — section-scoped Foundation Models parsing with grounding.

import Foundation

enum CareerResumeLLMStructuredParser {
    // MARK: - LLM response schema

    struct Response: Codable, Sendable, Equatable {
        struct ExperienceItem: Codable, Sendable, Equatable {
            var title: String
            var company: String?
            var location: String?
            var subtitle: String?
            var startDate: String?
            var endDate: String?
            var bullets: [String]?
        }

        struct ProjectItem: Codable, Sendable, Equatable {
            var title: String
            var term: String?
            var role: String?
            var bullets: [String]?
        }

        struct EducationItem: Codable, Sendable, Equatable {
            var institution: String
            var degree: String?
            var major: String?
            var gpa: String?
            var graduation: String?
            var bullets: [String]?
        }

        struct SkillGroupItem: Codable, Sendable, Equatable {
            var category: String
            var skills: [String]
        }

        var name: String?
        var email: String?
        var phone: String?
        var location: String?
        var links: [String]?
        var summary: String?
        var skills: [String]?
        var skillGroups: [SkillGroupItem]?
        var experience: [ExperienceItem]?
        var projects: [ProjectItem]?
        var education: [EducationItem]?
        var certifications: [String]?
    }

    struct PersonalResponse: Codable, Sendable, Equatable {
        var name: String?
        var email: String?
        var phone: String?
        var location: String?
        var links: [String]?
    }

    struct SectionListResponse<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
        var items: [T]?
    }

    struct SkillsResponse: Codable, Sendable, Equatable {
        var skills: [String]?
        var skillGroups: [Response.SkillGroupItem]?
    }

    struct SummaryResponse: Codable, Sendable, Equatable {
        var summary: String?
    }

    struct CertificationsResponse: Codable, Sendable, Equatable {
        var certifications: [String]?
    }

    // MARK: - Public API

    static func parse(plainText: String) async -> CareerResumeStructuredProfile? {
        guard CareerFoundationModelsJSONService.isAvailable() else { return nil }

        let segments = CareerResumeSectionSegmenter.segment(normalizedText: plainText)
        var response = Response()

        let preambleText = segments
            .filter { $0.kind == .preamble }
            .map(\.text)
            .joined(separator: "\n")

        if let personal = await parsePersonalSection(preambleText) {
            response.name = personal.name
            response.email = personal.email
            response.phone = personal.phone
            response.location = personal.location
            response.links = personal.links
        }

        if let summaryText = CareerResumeSectionSegmenter.text(for: .summary, in: segments),
           let summary = await parseSummarySection(summaryText) {
            response.summary = summary
        }

        async let experienceTask: [Response.ExperienceItem]? = {
            guard let text = CareerResumeSectionSegmenter.text(for: .experience, in: segments) else { return nil }
            return await parseExperienceSection(text)
        }()

        async let projectsTask: [Response.ProjectItem]? = {
            guard let text = CareerResumeSectionSegmenter.text(for: .projects, in: segments) else { return nil }
            return await parseProjectsSection(text)
        }()

        async let educationTask: [Response.EducationItem]? = {
            guard let text = CareerResumeSectionSegmenter.text(for: .education, in: segments) else { return nil }
            return await parseEducationSection(text)
        }()

        async let skillsTask: SkillsResponse? = {
            guard let text = CareerResumeSectionSegmenter.text(for: .skills, in: segments) else { return nil }
            return await parseSkillsSection(text)
        }()

        async let certificationsTask: [String]? = {
            guard let text = CareerResumeSectionSegmenter.text(for: .certifications, in: segments) else { return nil }
            return await parseCertificationsSection(text)
        }()

        response.experience = await experienceTask
        response.projects = await projectsTask
        response.education = await educationTask

        if let skills = await skillsTask {
            response.skills = skills.skills
            response.skillGroups = skills.skillGroups
        }

        response.certifications = await certificationsTask

        let profile = profile(from: response)
        return profile.hasContent ? profile : nil
    }

    static func profile(from response: Response) -> CareerResumeStructuredProfile {
        let groups = (response.skillGroups ?? []).map {
            CareerResumeStructuredProfile.SkillGroup(category: $0.category, skills: normalizeTokens($0.skills))
        }
        let flatSkills = normalizeTokens(response.skills)
        let resolvedSkills = flatSkills.isEmpty ? groups.flatMap(\.skills) : flatSkills

        return CareerResumeStructuredProfile(
            name: cleaned(response.name),
            email: cleaned(response.email),
            phone: cleaned(response.phone),
            location: cleaned(response.location),
            links: normalizeLinks(response.links),
            summary: cleaned(response.summary),
            skills: Array(resolvedSkills.prefix(60)),
            skillGroups: groups,
            education: (response.education ?? []).compactMap(makeEducationEntry),
            experience: (response.experience ?? []).compactMap(makeExperienceEntry),
            projects: (response.projects ?? []).compactMap(makeProjectEntry),
            certifications: normalizeTokens(response.certifications),
            otherSections: []
        )
    }

    // MARK: - Section parsers

    private static func parsePersonalSection(_ text: String) async -> PersonalResponse? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let prompt = """
        Extract contact fields from this resume header. Use ONLY text explicitly present.
        Do not invent email, phone, or links.

        Return strict JSON:
        { "name": String?, "email": String?, "phone": String?, "location": String?, "links": [String]? }

        Header text:
        \(text.prefix(2_000))
        """
        return await decodeJSON(prompt: prompt)
    }

    private static func parseSummarySection(_ text: String) async -> String? {
        let prompt = """
        Extract the professional summary from this section. Copy wording from the text only.
        Return strict JSON: { "summary": String? }

        Summary section:
        \(text.prefix(4_000))
        """
        let decoded: SummaryResponse? = await decodeJSON(prompt: prompt)
        return cleaned(decoded?.summary)
    }

    private static func parseExperienceSection(_ text: String) async -> [Response.ExperienceItem]? {
        let prompt = """
        Structure work experience entries from this section only.

        Rules:
        1. Use ONLY facts in the text. Do not invent employers, titles, dates, or bullets.
        2. One array item per role.
        3. title = job title only; company = employer only; location when present.
        4. subtitle = focus area — NOT dates, NOT a bullet.
        5. startDate/endDate as written (e.g. "June 2025", "August 2025").
        6. bullets = responsibility lines only — never another job title.
        7. Preserve full bullet sentences; do not split one bullet across items.

        Return strict JSON:
        { "items": [{
          "title": String,
          "company": String?,
          "location": String?,
          "subtitle": String?,
          "startDate": String?,
          "endDate": String?,
          "bullets": [String]?
        }] }

        Experience section:
        \(text.prefix(8_000))
        """
        let decoded: SectionListResponse<Response.ExperienceItem>? = await decodeJSON(prompt: prompt)
        return decoded?.items
    }

    private static func parseProjectsSection(_ text: String) async -> [Response.ProjectItem]? {
        let prompt = """
        Structure project entries from this section only.

        Rules:
        1. Use ONLY facts in the text.
        2. One array item per project with title, optional term, and bullets beneath it.
        3. Do not merge unrelated projects.

        Return strict JSON:
        { "items": [{
          "title": String,
          "term": String?,
          "role": String?,
          "bullets": [String]?
        }] }

        Projects section:
        \(text.prefix(6_000))
        """
        let decoded: SectionListResponse<Response.ProjectItem>? = await decodeJSON(prompt: prompt)
        return decoded?.items
    }

    private static func parseEducationSection(_ text: String) async -> [Response.EducationItem]? {
        let prompt = """
        Structure education entries from this section only.

        Rules:
        1. Use ONLY facts in the text.
        2. institution = school name; degree/major/gpa/graduation in their fields or bullets.
        3. Do not create placeholder schools.

        Return strict JSON:
        { "items": [{
          "institution": String,
          "degree": String?,
          "major": String?,
          "gpa": String?,
          "graduation": String?,
          "bullets": [String]?
        }] }

        Education section:
        \(text.prefix(4_000))
        """
        let decoded: SectionListResponse<Response.EducationItem>? = await decodeJSON(prompt: prompt)
        return decoded?.items
    }

    private static func parseSkillsSection(_ text: String) async -> SkillsResponse? {
        let prompt = """
        Extract skills from this section only.

        Rules:
        1. Use ONLY skills explicitly listed.
        2. When lines use "Category: skill, skill" format, populate skillGroups.
        3. Do not infer certifications (CISSP, Security+, etc.) from skills alone.

        Return strict JSON:
        {
          "skills": [String]?,
          "skillGroups": [{ "category": String, "skills": [String] }]?
        }

        Skills section:
        \(text.prefix(4_000))
        """
        return await decodeJSON(prompt: prompt)
    }

    private static func parseCertificationsSection(_ text: String) async -> [String]? {
        let prompt = """
        List certifications, licenses, or awards from this section only.
        Use ONLY text explicitly present. Return [] if none.

        Return strict JSON: { "certifications": [String]? }

        Certifications section:
        \(text.prefix(3_000))
        """
        let decoded: CertificationsResponse? = await decodeJSON(prompt: prompt)
        return decoded?.certifications
    }

    private static func decodeJSON<T: Decodable>(prompt: String) async -> T? {
        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Entry builders

    private static func makeExperienceEntry(_ item: Response.ExperienceItem) -> CareerResumeStructuredProfile.Entry? {
        let title = cleaned(item.title) ?? ""
        guard !title.isEmpty else { return nil }

        var headingLines: [String] = []

        // Jobright-style: company first, then title, then subtitle/dates.
        if let company = cleaned(item.company) {
            var companyLine = company
            if let location = cleaned(item.location) {
                companyLine += " – \(location)"
            }
            headingLines.append(companyLine)
        }
        headingLines.append(title)

        var detailParts: [String] = []
        if let subtitle = cleaned(item.subtitle) {
            detailParts.append(subtitle)
        }
        if let start = cleaned(item.startDate) {
            if let end = cleaned(item.endDate) {
                detailParts.append("\(start) – \(end)")
            } else {
                detailParts.append(start)
            }
        } else if let end = cleaned(item.endDate) {
            detailParts.append(end)
        }
        if !detailParts.isEmpty {
            headingLines.append(detailParts.joined(separator: " "))
        }

        let bullets = normalizeTokens(item.bullets)
        guard !headingLines.isEmpty || !bullets.isEmpty else { return nil }
        return .init(headingLines: headingLines, bullets: bullets)
    }

    private static func makeProjectEntry(_ item: Response.ProjectItem) -> CareerResumeStructuredProfile.Entry? {
        guard var titleLine = cleaned(item.title) else { return nil }
        if let term = cleaned(item.term) {
            titleLine += " \(term)"
        }

        var headingLines = [titleLine]
        if let role = cleaned(item.role) {
            headingLines.append(role)
        }

        let bullets = normalizeTokens(item.bullets)
        guard !bullets.isEmpty || !headingLines.isEmpty else { return nil }
        return .init(headingLines: headingLines, bullets: bullets)
    }

    private static func makeEducationEntry(_ item: Response.EducationItem) -> CareerResumeStructuredProfile.Entry? {
        guard let institution = cleaned(item.institution) else { return nil }

        var bullets: [String] = []
        if let degree = cleaned(item.degree) { bullets.append(degree) }
        if let major = cleaned(item.major) { bullets.append(major) }
        if let gpa = cleaned(item.gpa) { bullets.append("GPA: \(gpa)") }
        if let graduation = cleaned(item.graduation) { bullets.append(graduation) }
        bullets.append(contentsOf: normalizeTokens(item.bullets))

        var seen = Set<String>()
        bullets = bullets.filter { token in
            let key = token.lowercased()
            return seen.insert(key).inserted
        }

        return .init(headingLines: [institution], bullets: bullets)
    }

    // MARK: - Normalization

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeTokens(_ values: [String]?) -> [String] {
        guard let values else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func normalizeLinks(_ values: [String]?) -> [String] {
        normalizeTokens(values).prefix(8).map { link in
            link.lowercased().hasPrefix("www.") ? "https://" + link : link
        }
    }
}
