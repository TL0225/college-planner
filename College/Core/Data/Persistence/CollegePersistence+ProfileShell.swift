// CollegePersistence+ProfileShell.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+ProfileShell.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Profile shell writes (experiences, achievements) — Phase 7f local store-only.
@MainActor
extension CollegePersistence {
    @discardableResult
    func ensurePrimaryProfile() -> Profile? {
        if let existing = profile ?? (try? profileRepository.fetchPrimaryProfile()) {
            profile = existing
            return existing
        }
        do {
            let created = try profileRepository.ensurePrimaryProfileShell()
            profile = created
            bumpProfileRevision()
            return created
        } catch {
            AppLogger.shared.error(
                "ensurePrimaryProfile failed: \(error.localizedDescription)",
                category: .persistence
            )
            return nil
        }
    }

    func addExperience(
        title: String,
        company: String,
        location: String?,
        startDate: Date,
        endDate: Date?,
        isCurrent: Bool,
        description: String?,
        technologies: String? = nil
    ) {
        _ = try? profileRepository.createExperience(
            title: title,
            company: company,
            location: location,
            startDate: startDate,
            endDate: endDate,
            isCurrent: isCurrent,
            description: description,
            technologies: technologies
        )
        save()
        bumpProfileRevision()
    }

    func deleteExperience(_ experience: Experience) {
        try? profileRepository.deleteExperience(experience)
        save()
        bumpProfileRevision()
    }

    func addAchievement(
        name: String,
        organization: String,
        dateReceived: Date?,
        amount: String?,
        description: String?,
        url: String?
    ) {
        _ = try? profileRepository.createAchievement(
            name: name,
            organization: organization,
            dateReceived: dateReceived,
            amount: amount,
            description: description,
            url: url
        )
        save()
        bumpProfileRevision()
    }

    func deleteAchievement(_ achievement: Achievement) {
        try? profileRepository.deleteAchievement(achievement)
        save()
        bumpProfileRevision()
    }
}