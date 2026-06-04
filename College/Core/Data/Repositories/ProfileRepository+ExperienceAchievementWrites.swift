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
        description: String?
    ) throws -> Experience? {
        guard let shell = try fetchPrimaryProfile() else { return nil }
        let experience = Experience(isCurrent: isCurrent)
        experience.title = title
        experience.company = company
        experience.location = location
        experience.startDate = startDate
        experience.endDate = endDate
        experience.descriptionText = description
        experience.profile = shell
        context.insert(experience)
        ModelMergeCoalescer.scheduleSave(context)
        return experience
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