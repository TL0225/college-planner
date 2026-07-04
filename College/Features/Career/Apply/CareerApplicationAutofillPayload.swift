// CareerApplicationAutofillPayload.swift
// Feature: Career / Apply
// Purpose: Canonical apply-time payload assembled from Profile + ResumeSnapshot + Apply Profile.

import Foundation

struct CareerApplicationAutofillPayload: Codable, Sendable, Equatable {
    var personal: ApplyPersonalInfo
    var education: [ApplyEducationEntry]
    var experienceBlocks: [ApplyExperienceCompanyBlock]
    var projects: [ApplyProjectEntry]
    var skills: [String]
    var summary: String?
    var documents: ApplyDocuments
    var applicationProfile: ApplyApplicationProfile
    var approvedAt: Date
    var sourceRevisionToken: String?
}

struct ApplyPersonalInfo: Codable, Sendable, Equatable {
    var firstName: String
    var lastName: String
    var fullName: String
    var email: String?
    var phone: String?
    var address: String?
    var linkedInURL: String?
    var githubURL: String?
    var portfolioURL: String?
    var pronouns: String?
}

struct ApplyEducationEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var institution: String?
    var degree: String?
    var major: String?
    var graduation: String?
    var gpa: Double?
}

struct ApplyExperienceCompanyBlock: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var company: String
    var positions: [ApplyExperiencePosition]
}

struct ApplyExperiencePosition: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var location: String?
    var workArrangement: String?
    var employmentType: String?
    var startDate: String?
    var endDate: String?
    var isCurrent: Bool
    var bullets: [String]
}

struct ApplyProjectEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var role: String?
    var url: String?
    var technologies: String?
    var bullets: [String]
}

struct ApplyDocuments: Codable, Sendable, Equatable {
    var resumeDocumentID: UUID
    var resumeFileName: String
    var resumeFileURL: URL?
    var coverLetterDocumentID: UUID?
}

struct ApplyApplicationProfile: Codable, Sendable, Equatable {
    var workAuthorization: ApplyWorkAuthorization
    var preferences: ApplyApplicationDefaults
    var screeningAnswerCache: [String: ApplyScreeningAnswer]
    var allowEEOAutofill: Bool
}

struct ApplyWorkAuthorization: Codable, Sendable, Equatable {
    var usCitizen: Bool?
    var usAuthorized: Bool?
    var requiresSponsorshipNow: Bool?
    var requiresSponsorshipFuture: Bool?
    var countryOfCitizenship: String?
    var visaStatus: String?
}

struct ApplyApplicationDefaults: Codable, Sendable, Equatable {
    var willingToRelocate: String?
    var remotePreference: String?
    var salaryExpectation: String?
    var earliestStartDate: String?
    var referralSource: String?
}

struct ApplyScreeningAnswer: Codable, Sendable, Equatable {
    var answer: String
    var preferenceKey: String?
    var confirmedAt: Date
}
