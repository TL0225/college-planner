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

    init(
        id: UUID = UUID(),
        title: String,
        role: String = "",
        technologies: String = "",
        summary: String = "",
        projectURL: String = ""
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.technologies = technologies
        self.summary = summary
        self.projectURL = projectURL
    }
}
