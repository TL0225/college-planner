// CatalogSchoolDataPurge.swift
// Feature: Catalog
// Purpose: Catalog module — Report.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Clears on-disk catalog artifacts, local store scrape rows, ingest signatures, and designated program picks for a school.
@MainActor
enum CatalogSchoolDataPurge {
    struct Report: Sendable, Equatable {
        let schoolID: String
        let universityName: String
        let storePurgeCounts: CollegePersistence.CatalogScrapePurgeCounts
        let clearedSelectedProgramIDs: Int
        let removedFileStore: Bool
    }

    static func purgeNYU(collegePersistence: CollegePersistence) async throws -> Report {
        try await purge(
            schoolID: "new_york_university",
            universityName: "New York University",
            programURLNeedle: "bulletins.nyu",
            collegePersistence: collegePersistence
        )
    }

    static func purge(
        schoolID: String,
        universityName: String,
        catalogURL: String? = nil,
        collegePersistence: CollegePersistence
    ) async throws -> Report {
        let needle = programURLNeedle(forSchoolID: schoolID, catalogURL: catalogURL)
        return try await purge(
            schoolID: schoolID,
            universityName: universityName,
            programURLNeedle: needle,
            collegePersistence: collegePersistence
        )
    }

    private static func purge(
        schoolID: String,
        universityName: String,
        programURLNeedle: String?,
        collegePersistence: CollegePersistence
    ) async throws -> Report {
        let storePurgeCounts = collegePersistence.purgeCatalogScrapeData(
            forUniversityName: universityName,
            programURLContains: programURLNeedle
        )

        let clearedSelected = pruneDesignatedProgramSelections(universityName: universityName)

        CatalogSchoolRemoval.clearIngestMetadata(schoolID: schoolID)

        var removedFileStore = false
        if let university = collegePersistence.resolveUniversity(byName: universityName) {
            try? await CatalogVectorStore.shared.deleteAll(universityId: university.id)
        }
        do {
            try await CatalogSchoolRemoval.removeFileArtifacts(schoolID: schoolID, universityName: universityName)
            removedFileStore = true
        } catch CatalogSchoolRemoval.RemovalError.universityNotFound {
            removedFileStore = false
        }

        return Report(
            schoolID: schoolID,
            universityName: universityName,
            storePurgeCounts: storePurgeCounts,
            clearedSelectedProgramIDs: clearedSelected,
            removedFileStore: removedFileStore
        )
    }

    nonisolated static func programURLNeedle(forSchoolID schoolID: String, catalogURL: String?) -> String? {
        switch schoolID {
        case "new_york_university":
            return "bulletins.nyu"
        default:
            guard let catalogURL,
                  let host = URL(string: catalogURL)?.host?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !host.isEmpty else { return nil }
            return host
        }
    }

    /// Drops persisted “selected program scrape” picks for this university (Settings → Selected programs only).
    private static func pruneDesignatedProgramSelections(universityName: String) -> Int {
        let prefix = universityName.trimmingCharacters(in: .whitespacesAndNewlines) + " |"
        guard !prefix.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        let before = CatalogSelectedProgramsStore.allSelected()
        let remaining = before.filter { !$0.hasPrefix(prefix) }
        let removed = before.count - remaining.count
        if removed > 0 {
            CatalogSelectedProgramsStore.replace(remaining)
        }
        return removed
    }
}
