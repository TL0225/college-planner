// CatalogLayoutProfileRegistry.swift
// Feature: Catalog
// Purpose: Loads bundled layout profile metadata and school overrides for CourseLeafProfileConfig.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogLayoutProfileEntry: Codable, Sendable, Equatable {
    let id: String
    let label: String
    let schoolIDs: [String]
    let domSignals: [String]
}

enum CatalogLayoutProfileRegistry {
    private struct RegistryFile: Codable {
        let profiles: [CatalogLayoutProfileEntry]
    }

    private static let bundledEntries: [CatalogLayoutProfileEntry] = loadBundled()

    static func entries() -> [CatalogLayoutProfileEntry] {
        bundledEntries
    }

    static func preferredProfileID(forSchoolID schoolID: String) -> CourseLeafLayoutProfileID? {
        let trimmed = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for entry in bundledEntries where entry.schoolIDs.contains(trimmed) {
            return CourseLeafLayoutProfileID.resolve(entry.id)
        }
        return nil
    }

    /// School override store → bundled registry → classifier output.
    static func resolvedProfileID(
        forSchoolID schoolID: String,
        classifiedProfile: CourseLeafLayoutProfileID
    ) -> CourseLeafLayoutProfileID {
        if let override = SchoolLayoutOverrideStore.load(schoolID: schoolID) {
            return CourseLeafLayoutProfileID.resolve(override.profileID)
        }
        if let preferred = preferredProfileID(forSchoolID: schoolID) {
            return preferred
        }
        return classifiedProfile
    }

    static func profileConfig(
        for profileID: CourseLeafLayoutProfileID,
        schoolID: String? = nil
    ) -> CourseLeafProfileConfig {
        if let schoolID,
           let preferred = preferredProfileID(forSchoolID: schoolID),
           preferred == profileID {
            return CourseLeafProfileConfig.config(for: profileID)
        }
        return CourseLeafProfileConfig.config(for: profileID)
    }

    static func legacyCrawlConfig(forSchoolID schoolID: String) -> CourseLeafProfileConfig {
        if let preferred = preferredProfileID(forSchoolID: schoolID) {
            return CourseLeafProfileConfig.config(for: preferred)
        }
        return CourseLeafProfileConfig.config(for: .profileDefault)
    }

    private static func loadBundled() -> [CatalogLayoutProfileEntry] {
        guard let url = Bundle.main.url(
            forResource: "CatalogProfileRegistry",
            withExtension: "json",
            subdirectory: nil
        ) ?? Bundle.main.url(
            forResource: "CatalogProfileRegistry",
            withExtension: "json",
            subdirectory: "Features/Catalog/Ingest"
        ) else {
            return fallbackEntries()
        }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RegistryFile.self, from: data) else {
            return fallbackEntries()
        }
        return file.profiles
    }

    /// Validates a profile entry before programmatic registry adoption (bundled JSON is grandfathered).
    static func validateRegistryAdoption(_ entry: CatalogLayoutProfileEntry) -> String? {
        guard !entry.schoolIDs.isEmpty else { return nil }
        return CatalogLayoutProfileGovernance.validateNewProfileEntry(entry)
    }

    private static func fallbackEntries() -> [CatalogLayoutProfileEntry] {
        [
            CatalogLayoutProfileEntry(
                id: "profileA",
                label: "NYU-style",
                schoolIDs: ["new_york_university"],
                domSignals: ["detail_code"]
            ),
            CatalogLayoutProfileEntry(
                id: "profileB",
                label: "Fordham-style",
                schoolIDs: ["fordham_university"],
                domSignals: ["courseblocktitle"]
            ),
            CatalogLayoutProfileEntry(
                id: "profileC",
                label: "CMU-style",
                schoolIDs: ["carnegie_mellon_university"],
                domSignals: ["dl.courseblock"]
            ),
            CatalogLayoutProfileEntry(
                id: "profileDefault",
                label: "Default",
                schoolIDs: [],
                domSignals: []
            ),
        ]
    }
}
