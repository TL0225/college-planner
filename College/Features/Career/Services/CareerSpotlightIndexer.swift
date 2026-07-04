// CareerSpotlightIndexer.swift
// Feature: Career
// Purpose: Career module — CareerSpotlightIndexer.
// Data: CollegePersistence / repositories when applicable.

import CollegeCareer
import CoreSpotlight
import UniformTypeIdentifiers

enum CareerSpotlightIndexer {
    private struct ApplicationSpotlightSnapshot: Sendable {
        let id: UUID
        let title: String?
        let company: String?
        let locationText: String?
        let source: String?
        let statusDisplayName: String

        init(application: JobApplication) {
            id = application.id
            title = application.title
            company = application.company
            locationText = application.locationText
            source = application.source
            statusDisplayName = CareerApplicationPresentation.status(for: application).displayName
        }
    }

    static func index(application: JobApplication) {
        let snapshot = ApplicationSpotlightSnapshot(application: application)
        Task { @MainActor in
            await BackgroundServiceOnDemand.run(id: "career_spotlight_index") {
                indexApplication(snapshot)
            }
        }
    }

    private static func indexApplication(_ application: ApplicationSpotlightSnapshot) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = application.title
        attributeSet.contentDescription = [
            application.company,
            application.statusDisplayName,
            application.locationText,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        attributeSet.keywords = [
            application.company,
            application.title,
            application.source,
            application.locationText,
            application.statusDisplayName,
        ].compactMap { $0 }

        let item = CSSearchableItem(
            uniqueIdentifier: "career.application.\(application.id.uuidString)",
            domainIdentifier: "career.board",
            attributeSet: attributeSet
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func remove(application: JobApplication) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ["career.application.\(application.id.uuidString)"]
        )
    }

    static func index(employer name: String, slug: String, careersURL: String?, openRoleCount: Int?) {
        Task { @MainActor in
            await BackgroundServiceOnDemand.run(id: "career_spotlight_index") {
                indexEmployer(name: name, slug: slug, careersURL: careersURL, openRoleCount: openRoleCount)
            }
        }
    }

    private static func indexEmployer(name: String, slug: String, careersURL: String?, openRoleCount: Int?) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = name
        attributeSet.contentDescription = [
            careersURL,
            openRoleCount.map { "\($0) openings" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        attributeSet.keywords = [name, slug, "employer", "job board"]

        let item = CSSearchableItem(
            uniqueIdentifier: "career.employer.\(slug)",
            domainIdentifier: "career.jobboards",
            attributeSet: attributeSet
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func removeEmployer(slug: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["career.employer.\(slug)"])
    }
}
