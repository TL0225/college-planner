// ResumeSnapshot.swift
// Feature: Resume
// Purpose: Raw read-only value models captured from Profile for resume generation.

import Foundation

// MARK: - Contact links

enum ResumeContactLinkKind: String, Codable, Sendable, Hashable {
    case linkedIn
    case github
    case website
}

struct ResumeContactLink: Codable, Sendable, Hashable, Equatable {
    var kind: ResumeContactLinkKind
    var url: String
    var displayLabel: String
}

// MARK: - Section entries

struct ResumePersonalInfo: Codable, Sendable, Hashable, Equatable {
    var name: String
    var pronouns: String?
    var email: String?
    var phone: String?
    var address: String?
    var contactLinks: [ResumeContactLink]
}

struct ResumeEducationEntry: Codable, Sendable, Hashable, Equatable, Identifiable {
    var id: UUID
    var degreeLevel: String?
    var major: String?
    var collegeName: String?
    var gpa: Double?
    var expectedGraduation: String?
}

struct ResumeExperienceEntry: Codable, Sendable, Hashable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var company: String
    var location: String?
    var dateRange: String
    var descriptionText: String?
    var technologies: String?
}

struct ResumeProjectEntry: Codable, Sendable, Hashable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var role: String?
    var technologies: String?
    var summary: String?
    var projectURL: String?
    var dateRange: String?
    var bullets: [String]
}

struct ResumeAchievementEntry: Codable, Sendable, Hashable, Equatable, Identifiable {
    var id: UUID
    var name: String?
    var organization: String?
    var dateReceived: String?
    var descriptionText: String?
}

struct ResumeExtracurricularEntry: Codable, Sendable, Hashable, Equatable, Identifiable {
    var id: UUID
    var organization: String
    var role: String?
    var dateRange: String?
    var descriptionText: String?
}

// MARK: - Snapshot

struct ResumeSnapshot: Codable, Sendable, Hashable, Equatable {
    var snapshotID: UUID
    var sourceProfileID: UUID
    var capturedAt: Date
    var profileRevisionToken: String
    var personal: ResumePersonalInfo
    var summary: String?
    var education: [ResumeEducationEntry]
    var experiences: [ResumeExperienceEntry]
    var projects: [ResumeProjectEntry]
    var skills: [String]
    var achievements: [ResumeAchievementEntry]
    var certifications: [String]
    var extracurriculars: [ResumeExtracurricularEntry]

    init(
        snapshotID: UUID,
        sourceProfileID: UUID,
        capturedAt: Date,
        profileRevisionToken: String,
        personal: ResumePersonalInfo,
        summary: String? = nil,
        education: [ResumeEducationEntry],
        experiences: [ResumeExperienceEntry],
        projects: [ResumeProjectEntry],
        skills: [String],
        achievements: [ResumeAchievementEntry] = [],
        certifications: [String] = [],
        extracurriculars: [ResumeExtracurricularEntry] = []
    ) {
        self.snapshotID = snapshotID
        self.sourceProfileID = sourceProfileID
        self.capturedAt = capturedAt
        self.profileRevisionToken = profileRevisionToken
        self.personal = personal
        self.summary = summary
        self.education = education
        self.experiences = experiences
        self.projects = projects
        self.skills = skills
        self.achievements = achievements
        self.certifications = certifications
        self.extracurriculars = extracurriculars
    }
}
