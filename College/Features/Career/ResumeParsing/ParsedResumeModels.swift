// ParsedResumeModels.swift
// Feature: Career / ResumeParsing
// Purpose: Typed parsed resume models for apply-grade accuracy.

import Foundation

enum ParsedEmploymentType: String, Codable, Sendable, CaseIterable {
    case fullTime, partTime, internship, externship, coOp, contract, volunteer
}

struct ParsedExperience: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var company: String
    var location: String?
    var workArrangement: String?
    var employmentType: ParsedEmploymentType?
    var startDate: String?
    var endDate: String?
    var isCurrent: Bool
    var bullets: [String]
}

struct ParsedProject: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var role: String?
    var url: String?
    var technologies: String?
    var bullets: [String]
}

struct ParsedEducation: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var institution: String?
    var degree: String?
    var major: String?
    var gpa: Double?
    var graduation: String?
}

struct ParsedResumeDocument: Codable, Sendable, Equatable {
    var personalName: String?
    var email: String?
    var phone: String?
    var summary: String?
    var experiences: [ParsedExperience]
    var projects: [ParsedProject]
    var education: [ParsedEducation]
    var skills: [String]
    var format: ResumeFormatKind
}

enum ResumeFormatKind: String, Codable, Sendable {
    case chronological, functional, hybrid, student, academicCV, unknown
}
