// CareerResumeProfileAutofillService.swift
// Feature: Career
// Purpose: Map parsed resume structured profile into Profile / Experience / Projects.

import Foundation
import SwiftData

enum ProfileAutofillFieldID: String, Hashable, Sendable, CaseIterable {
    case name
    case email
    case phone
    case location
    case links
    case skills
    case university
    case degreeType
    case major
    case graduationYear
}

struct ScalarAutofillItem: Identifiable, Sendable, Hashable {
    let id: ProfileAutofillFieldID
    let section: String
    let label: String
    let proposedValue: String
}

struct ExperienceAutofillEntry: Identifiable, Sendable, Hashable {
    let id: String
    var title: String
    var company: String
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var isCurrent: Bool
    var descriptionText: String
    var technologies: String?
}

struct ProjectAutofillEntry: Identifiable, Sendable, Hashable {
    let id: String
    var project: PortfolioProject
}

struct ProfileAutofillDiff: Sendable {
    var scalarItems: [ScalarAutofillItem]
    var experiences: [ExperienceAutofillEntry]
    var projects: [ProjectAutofillEntry]

    var isEmpty: Bool {
        scalarItems.isEmpty && experiences.isEmpty && projects.isEmpty
    }
}

struct ProfileAutofillSelection: Sendable {
    var enabledScalarFields: Set<ProfileAutofillFieldID>
    var enabledExperienceIDs: Set<String>
    var enabledProjectIDs: Set<String>

    static func allEnabled(from diff: ProfileAutofillDiff) -> ProfileAutofillSelection {
        ProfileAutofillSelection(
            enabledScalarFields: Set(diff.scalarItems.map(\.id)),
            enabledExperienceIDs: Set(diff.experiences.map(\.id)),
            enabledProjectIDs: Set(diff.projects.map(\.id))
        )
    }

    static let noneEnabled = ProfileAutofillSelection(
        enabledScalarFields: [],
        enabledExperienceIDs: [],
        enabledProjectIDs: []
    )
}

enum CareerResumeProfileAutofillService {
    static func diff(
        structuredProfile: CareerResumeStructuredProfile,
        existingProfile: Profile,
        existingAcademicProfile: AcademicProfile?
    ) -> ProfileAutofillDiff {
        var scalarItems: [ScalarAutofillItem] = []

        if let name = structuredProfile.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           isEmpty(existingProfile.name) {
            scalarItems.append(.init(id: .name, section: "Identity", label: "Name", proposedValue: name))
        }

        if let email = preferredEmail(from: structuredProfile),
           isEmpty(existingProfile.universityEmail) {
            scalarItems.append(.init(id: .email, section: "Contact", label: "University email", proposedValue: email))
        }

        if let phone = structuredProfile.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty,
           isEmpty(existingProfile.personalPhone) {
            scalarItems.append(.init(id: .phone, section: "Contact", label: "Phone", proposedValue: phone))
        }

        if let location = structuredProfile.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty,
           isEmpty(existingProfile.permanentAddress) {
            scalarItems.append(.init(id: .location, section: "Contact", label: "Address", proposedValue: location))
        }

        let proposedLinks = structuredProfile.links
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let existingLinks = existingProfile.linksList
        let newLinks = proposedLinks.filter { link in
            !existingLinks.contains { $0.caseInsensitiveCompare(link) == .orderedSame }
        }
        if !newLinks.isEmpty {
            let display = (existingLinks + newLinks).joined(separator: ", ")
            scalarItems.append(.init(id: .links, section: "Contact", label: "Links", proposedValue: display))
        }

        let proposedSkills = structuredProfile.skills
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let existingSkills = existingProfile.skillsList
        let newSkills = proposedSkills.filter { skill in
            !existingSkills.contains { $0.caseInsensitiveCompare(skill) == .orderedSame }
        }
        if !newSkills.isEmpty {
            let display = (existingSkills + newSkills).joined(separator: ", ")
            scalarItems.append(.init(id: .skills, section: "Skills", label: "Skills", proposedValue: display))
        }

        if let education = structuredProfile.education.first {
            let parsed = parseEducation(education)
            let academic = existingAcademicProfile

            if let university = parsed.university,
               isEmpty(academic?.collegeName) && isEmpty(existingProfile.collegeName) {
                scalarItems.append(.init(id: .university, section: "Education", label: "University", proposedValue: university))
            }

            if let degreeType = parsed.degreeType,
               isEmpty(academic?.degreeType) {
                scalarItems.append(.init(id: .degreeType, section: "Education", label: "Degree", proposedValue: degreeType))
            }

            if let major = parsed.major,
               (academic?.majorsCSV ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               (academic?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scalarItems.append(.init(id: .major, section: "Education", label: "Major", proposedValue: major))
            }

            if let year = parsed.graduationYear,
               academic?.expectedGraduationYear == nil || academic?.expectedGraduationYear == 0 {
                scalarItems.append(.init(id: .graduationYear, section: "Education", label: "Graduation year", proposedValue: String(year)))
            }
        }

        let existingExperienceKeys = Set(
            (existingProfile.experiences ?? []).map {
                experienceMatchKey(title: $0.title ?? "", company: $0.company ?? "")
            }
        )
        let experiences = structuredProfile.experience.compactMap { entry -> ExperienceAutofillEntry? in
            guard let mapped = mapExperience(entry) else { return nil }
            let key = experienceMatchKey(title: mapped.title, company: mapped.company)
            guard !existingExperienceKeys.contains(key) else { return nil }
            return ExperienceAutofillEntry(
                id: key,
                title: mapped.title,
                company: mapped.company,
                location: mapped.location,
                startDate: mapped.startDate,
                endDate: mapped.endDate,
                isCurrent: mapped.isCurrent,
                descriptionText: mapped.descriptionText,
                technologies: mapped.technologies
            )
        }

        let existingProjectTitles = Set(
            existingProfile.portfolioProjectsList.map {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        let projects = structuredProfile.projects.compactMap { entry -> ProjectAutofillEntry? in
            guard let project = mapProject(entry, resumeLinks: structuredProfile.links) else { return nil }
            let key = project.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !existingProjectTitles.contains(key) else { return nil }
            return ProjectAutofillEntry(id: key, project: project)
        }

        return ProfileAutofillDiff(
            scalarItems: scalarItems,
            experiences: experiences,
            projects: projects
        )
    }

    @MainActor
    static func apply(
        _ diff: ProfileAutofillDiff,
        selection: ProfileAutofillSelection,
        using persistence: CollegePersistence
    ) {
        guard let profile = persistence.ensurePrimaryProfile() else { return }

        for item in diff.scalarItems where selection.enabledScalarFields.contains(item.id) {
            switch item.id {
            case .name:
                profile.name = item.proposedValue
            case .email:
                profile.universityEmail = item.proposedValue
            case .phone:
                profile.personalPhone = item.proposedValue
            case .location:
                profile.permanentAddress = item.proposedValue
            case .links:
                profile.linksList = item.proposedValue
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            case .skills:
                profile.skillsList = item.proposedValue
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            case .university:
                profile.collegeName = item.proposedValue
                if let academic = persistence.ensurePrimaryAcademicProfile() {
                    academic.collegeName = item.proposedValue
                }
            case .degreeType:
                if let academic = persistence.ensurePrimaryAcademicProfile() {
                    academic.degreeType = item.proposedValue
                    if let normalized = DegreeTypeNormalizer.normalize(item.proposedValue) {
                        academic.degreeLevel = normalized.degreeLevel
                    }
                }
            case .major:
                persistence.syncPrimaryPrograms(majors: [item.proposedValue], minors: persistence.resolvedMinorNames())
            case .graduationYear:
                if let academic = persistence.ensurePrimaryAcademicProfile(),
                   let year = Int16(item.proposedValue) {
                    academic.expectedGraduationYear = year
                    academic.expectedGraduation = item.proposedValue
                }
            }
        }

        for entry in diff.experiences where selection.enabledExperienceIDs.contains(entry.id) {
            _ = try? persistence.profileRepository.upsertExperienceFromResume(
                title: entry.title,
                company: entry.company,
                location: entry.location,
                startDate: entry.startDate ?? Date(),
                endDate: entry.endDate,
                isCurrent: entry.isCurrent,
                description: entry.descriptionText,
                technologies: entry.technologies
            )
        }

        var portfolio = profile.portfolioProjectsList
        for entry in diff.projects where selection.enabledProjectIDs.contains(entry.id) {
            portfolio.append(entry.project)
        }
        if !diff.projects.isEmpty {
            profile.portfolioProjectsList = portfolio
        }

        persistence.save()
        persistence.bumpProfileRevision()
    }

    // MARK: - Mapping helpers

    private static func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func preferredEmail(from profile: CareerResumeStructuredProfile) -> String? {
        guard let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return nil
        }
        if email.lowercased().hasSuffix(".edu") { return email }
        return email
    }

    private static func experienceMatchKey(title: String, company: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedTitle)|\(normalizedCompany)"
    }

    private struct MappedExperience {
        var title: String
        var company: String
        var location: String?
        var startDate: Date?
        var endDate: Date?
        var isCurrent: Bool
        var descriptionText: String
        var technologies: String?
    }

    private static func mapExperience(_ entry: CareerResumeStructuredProfile.Entry) -> MappedExperience? {
        let lines = entry.headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let combined = lines.joined(separator: " ")
        let dateHeading = lines.last(where: { CareerResumeDateParser.parseDateRange(from: $0) != nil }) ?? combined
        let dateRange = CareerResumeDateParser.parseDateRange(from: dateHeading)
        let isCurrent = combined.lowercased().contains("present")
            || combined.lowercased().contains("current")

        var title = lines[0]
        var company = lines.count > 1 ? lines[1] : ""
        var location: String? = lines.count > 2 ? lines[2] : nil

        if company.isEmpty, let dashSplit = splitTitleCompany(from: title) {
            title = dashSplit.title
            company = dashSplit.company
            location = dashSplit.location ?? location
        }

        title = stripDates(from: title)
        company = stripDates(from: company)
        location = location.map(stripDates(from:))

        guard !title.isEmpty, !company.isEmpty else { return nil }

        let descriptionText = entry.bullets.joined(separator: "\n")
        let technologies = inferTechnologies(from: entry)

        return MappedExperience(
            title: title,
            company: company,
            location: location,
            startDate: dateRange?.start,
            endDate: isCurrent ? nil : dateRange?.end,
            isCurrent: isCurrent,
            descriptionText: descriptionText,
            technologies: technologies
        )
    }

    private static func mapProject(
        _ entry: CareerResumeStructuredProfile.Entry,
        resumeLinks: [String]
    ) -> PortfolioProject? {
        let lines = entry.headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let titleLine = lines.first else { return nil }

        let combined = lines.joined(separator: " ")
        let dateRange = CareerResumeDateParser.parseDateRange(from: combined)
        let isCurrent = combined.lowercased().contains("present")
            || combined.lowercased().contains("current")

        let title = stripDates(from: titleLine)
        guard !title.isEmpty else { return nil }

        let role = lines.count > 1 ? stripDates(from: lines[1]) : ""
        let technologies = lines.dropFirst().joined(separator: ", ")

        let githubURL = resumeLinks.first {
            $0.lowercased().contains("github.com")
        }
        let projectURL = resumeLinks.first {
            !$0.lowercased().contains("github.com") && ($0.hasPrefix("http://") || $0.hasPrefix("https://"))
        } ?? ""

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        let startDateString = dateRange.map { formatter.string(from: $0.start) }
        let endDateString: String? = {
            if isCurrent { return "Present" }
            guard let end = dateRange?.end else { return nil }
            return formatter.string(from: end)
        }()

        return PortfolioProject(
            title: title,
            role: role,
            technologies: technologies,
            summary: entry.bullets.joined(separator: " "),
            projectURL: projectURL,
            startDateString: startDateString,
            endDateString: endDateString,
            githubURL: githubURL,
            bullets: entry.bullets
        )
    }

    private struct ParsedEducation {
        var university: String?
        var degreeType: String?
        var major: String?
        var graduationYear: Int?
    }

    private static func parseEducation(_ entry: CareerResumeStructuredProfile.Entry) -> ParsedEducation {
        let combined = entry.headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        var result = ParsedEducation()
        result.university = entry.headingLines.first.map(stripDates(from:))

        if let degreeMatch = combined.range(
            of: #"(?i)\b(b\.?\s?s\.?|b\.?\s*a\.?|m\.?\s?s\.?|m\.?\s*a\.?|ph\.?\s*d\.?|b\.?\s*eng\.?)\b"#,
            options: .regularExpression
        ) {
            result.degreeType = String(combined[degreeMatch])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
        }

        if let majorMatch = combined.range(
            of: #"(?i)(?:in|major[:\s]+)\s*([A-Za-z][A-Za-z\s&/-]{2,})"#,
            options: .regularExpression
        ) {
            let token = String(combined[majorMatch])
            result.major = token
                .replacingOccurrences(of: #"(?i)^(in|major)[:\s]+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let degreeType = result.degreeType {
            let remainder = combined
                .replacingOccurrences(of: degreeType, with: "", options: .caseInsensitive)
                .replacingOccurrences(of: result.university ?? "", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: " |,-–—"))
            if remainder.count > 2 {
                result.major = remainder
            }
        }

        if let dateRange = CareerResumeDateParser.parseDateRange(from: combined) {
            result.graduationYear = Calendar.current.component(.year, from: dateRange.end)
        } else if let yearMatch = combined.range(of: #"\b(20\d{2}|19\d{2})\b"#, options: .regularExpression) {
            result.graduationYear = Int(combined[yearMatch])
        }

        return result
    }

    private struct TitleCompanySplit {
        var title: String
        var company: String
        var location: String?
    }

    private static func splitTitleCompany(from line: String) -> TitleCompanySplit? {
        let separators = [" – ", " — ", " - ", " | ", " at "]
        for separator in separators {
            let parts = line.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                return TitleCompanySplit(
                    title: parts[0],
                    company: parts[1],
                    location: parts.count > 2 ? parts[2] : nil
                )
            }
        }
        return nil
    }

    private static func stripDates(from text: String) -> String {
        var cleaned = text
        let patterns = [
            #"(?i)\s*\(?\d{4}\s*[–\-—]\s*(\d{4}|present|current|now)\)?"#,
            #"(?i)\s*\(?\(?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4}\s*[–\-—]\s*((jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4}|present|current|now)\)?"#,
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,|–—-"))
    }

    private static func inferTechnologies(from entry: CareerResumeStructuredProfile.Entry) -> String? {
        let corpus = (entry.headingLines + entry.bullets).joined(separator: " ")
        let techPattern = #"(?i)\b(swift|python|java|javascript|typescript|react|node\.?js|sql|aws|azure|gcp|docker|kubernetes|git|linux|c\+\+|c#|go|rust|kotlin)\b"#
        guard let regex = try? NSRegularExpression(pattern: techPattern) else { return nil }
        let range = NSRange(corpus.startIndex..., in: corpus)
        let matches = regex.matches(in: corpus, range: range)
        let tokens = matches.compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: corpus) else { return nil }
            return String(corpus[swiftRange])
        }
        let unique = Array(Set(tokens.map { $0.capitalized })).sorted()
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}

extension Notification.Name {
    static let careerResumeReadyForProfileImport = Notification.Name("careerResumeReadyForProfileImport")
}
