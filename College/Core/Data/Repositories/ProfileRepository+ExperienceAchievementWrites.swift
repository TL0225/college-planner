// ProfileRepository+ExperienceAchievementWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+ExperienceAchievementWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    @discardableResult
    func createExperience(
        title: String,
        company: String,
        location: String?,
        startDate: Date,
        endDate: Date?,
        isCurrent: Bool,
        description: String?,
        technologies: String? = nil
    ) throws -> Experience? {
        guard let shell = try fetchPrimaryProfile() else { return nil }
        let experience = Experience(isCurrent: isCurrent)
        experience.title = title
        experience.company = company
        experience.location = location
        experience.startDate = startDate
        experience.endDate = endDate
        experience.descriptionText = description
        experience.technologies = technologies
        experience.profile = shell
        context.insert(experience)
        ModelMergeCoalescer.scheduleSave(context)
        return experience
    }

    /// Upserts an experience row keyed by normalized title + company.
    @discardableResult
    func upsertExperienceFromResume(
        title: String,
        company: String,
        location: String?,
        startDate: Date?,
        endDate: Date?,
        isCurrent: Bool,
        description: String?,
        technologies: String?
    ) throws -> Experience? {
        guard let shell = try fetchPrimaryProfile() else { return nil }
        let key = Self.experienceMatchKey(title: title, company: company)
        let existing = (shell.experiences ?? []).first {
            Self.experienceMatchKey(title: $0.title ?? "", company: $0.company ?? "") == key
        }

        let experience = existing ?? Experience(isCurrent: isCurrent)
        experience.title = title
        experience.company = company
        experience.location = location
        experience.startDate = startDate
        experience.endDate = endDate
        experience.isCurrent = isCurrent
        experience.descriptionText = description
        if let technologies, !technologies.isEmpty {
            experience.technologies = technologies
        }
        experience.profile = shell
        if existing == nil {
            context.insert(experience)
        }
        ModelMergeCoalescer.scheduleSave(context)
        return experience
    }

    private static func experienceMatchKey(title: String, company: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedTitle)|\(normalizedCompany)"
    }

    func deleteExperience(_ experience: Experience) throws {
        context.delete(experience)
        ModelMergeCoalescer.scheduleSave(context)
    }

    @discardableResult
    func createAchievement(
        name: String,
        organization: String,
        dateReceived: Date?,
        amount: String?,
        description: String?,
        url: String?
    ) throws -> Achievement? {
        guard let shell = try fetchPrimaryProfile() else { return nil }
        let achievement = Achievement()
        achievement.name = name
        achievement.organization = organization
        achievement.dateReceived = dateReceived
        achievement.amount = amount
        achievement.descriptionText = description
        achievement.url = url
        achievement.profile = shell
        context.insert(achievement)
        ModelMergeCoalescer.scheduleSave(context)
        return achievement
    }

    func deleteAchievement(_ achievement: Achievement) throws {
        context.delete(achievement)
        ModelMergeCoalescer.scheduleSave(context)
    }
}