// PortfolioProject.swift
// Feature: Profile
// Purpose: Profile module — PortfolioProject.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct PortfolioProject: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var role: String
    var technologies: String
    var summary: String
    var projectURL: String
    var startDateString: String?
    var endDateString: String?
    var githubURL: String?
    var bullets: [String]

    init(
        id: UUID = UUID(),
        title: String,
        role: String = "",
        technologies: String = "",
        summary: String = "",
        projectURL: String = "",
        startDateString: String? = nil,
        endDateString: String? = nil,
        githubURL: String? = nil,
        bullets: [String] = []
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.technologies = technologies
        self.summary = summary
        self.projectURL = projectURL
        self.startDateString = startDateString
        self.endDateString = endDateString
        self.githubURL = githubURL
        self.bullets = bullets
    }
}
