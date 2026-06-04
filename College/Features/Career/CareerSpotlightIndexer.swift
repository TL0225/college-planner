// CareerSpotlightIndexer.swift
// Feature: Career
// Purpose: Career module — CareerSpotlightIndexer.
// Data: CollegePersistence / repositories when applicable.

import CoreSpotlight
import UniformTypeIdentifiers

enum CareerSpotlightIndexer {
    static func index(application: JobApplication) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = application.title
        attributeSet.contentDescription = [
            application.company,
            CareerApplicationPresentation.status(for: application).displayName,
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
            CareerApplicationPresentation.status(for: application).displayName,
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
}
