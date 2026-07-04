// CareerResumeStructuredProfile+Codable.swift
// Feature: Career / ResumeParsing
// Purpose: Backward-compatible decoding when new fields are added to structured profile JSON.

import Foundation

extension CareerResumeStructuredProfile {
    enum CodingKeys: String, CodingKey {
        case name, email, phone, location, links, summary, skills, skillGroups
        case education, experience, projects, certifications, otherSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        links = try container.decodeIfPresent([String].self, forKey: .links) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
        skillGroups = try container.decodeIfPresent([SkillGroup].self, forKey: .skillGroups) ?? []
        education = try container.decodeIfPresent([Entry].self, forKey: .education) ?? []
        experience = try container.decodeIfPresent([Entry].self, forKey: .experience) ?? []
        projects = try container.decodeIfPresent([Entry].self, forKey: .projects) ?? []
        certifications = try container.decodeIfPresent([String].self, forKey: .certifications) ?? []
        otherSections = try container.decodeIfPresent([FreeSection].self, forKey: .otherSections) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(skills, forKey: .skills)
        if !skillGroups.isEmpty {
            try container.encode(skillGroups, forKey: .skillGroups)
        }
        try container.encode(education, forKey: .education)
        try container.encode(experience, forKey: .experience)
        try container.encode(projects, forKey: .projects)
        try container.encode(certifications, forKey: .certifications)
        try container.encode(otherSections, forKey: .otherSections)
    }
}
