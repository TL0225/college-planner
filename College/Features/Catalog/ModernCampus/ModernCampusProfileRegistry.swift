// ModernCampusProfileRegistry.swift
// Feature: Catalog
// Purpose: Bundled school → Modern Campus layout profile priors.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ModernCampusProfileRegistryEntry: Codable, Sendable, Equatable {
    let id: String
    let label: String
    let schoolIDs: [String]
    let domSignals: [String]
}

enum ModernCampusProfileRegistry {
    private struct RegistryFile: Codable {
        let profiles: [ModernCampusProfileRegistryEntry]
    }

    private static let bundledEntries: [ModernCampusProfileRegistryEntry] = loadBundled()

    static func entries() -> [ModernCampusProfileRegistryEntry] {
        bundledEntries
    }

    static func preferredProfileID(forSchoolID schoolID: String) -> ModernCampusLayoutProfileID? {
        let trimmed = schoolID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for entry in bundledEntries where entry.schoolIDs.contains(trimmed) {
            return ModernCampusLayoutProfileID.resolve(entry.id)
        }
        return nil
    }

    /// School override store → bundled registry → host profile heuristic.
    static func resolvedProfileID(
        forSchoolID schoolID: String,
        host: String?,
        classifiedProfile: ModernCampusLayoutProfileID
    ) -> ModernCampusLayoutProfileID {
        if let override = SchoolLayoutOverrideStore.load(schoolID: schoolID) {
            return ModernCampusLayoutProfileID.resolve(override.profileID)
        }
        if let preferred = preferredProfileID(forSchoolID: schoolID) {
            return preferred
        }
        if ModernCampusHostProfiles.resolve(host: host)?.prefersEntityPageProgramDiscovery == true {
            return .entityPreviewProgram
        }
        return classifiedProfile
    }

    private static func loadBundled() -> [ModernCampusProfileRegistryEntry] {
        guard let url = Bundle.main.url(
            forResource: "ModernCampusProfileRegistry",
            withExtension: "json",
            subdirectory: nil
        ) ?? Bundle.main.url(
            forResource: "ModernCampusProfileRegistry",
            withExtension: "json",
            subdirectory: "Features/Catalog/ModernCampus"
        ) else {
            return fallbackEntries()
        }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RegistryFile.self, from: data) else {
            return fallbackEntries()
        }
        return file.profiles
    }

    private static func fallbackEntries() -> [ModernCampusProfileRegistryEntry] {
        [
            ModernCampusProfileRegistryEntry(
                id: ModernCampusLayoutProfileID.sidebarN2Links.rawValue,
                label: "Sidebar N2 links",
                schoolIDs: [
                    "dakota_state_university",
                    "stony_brook",
                    "purdue_university",
                    "ohio_university",
                ],
                domSignals: ["n2_links"]
            ),
            ModernCampusProfileRegistryEntry(
                id: ModernCampusLayoutProfileID.entityPreviewProgram.rawValue,
                label: "Entity preview program",
                schoolIDs: ["university_at_buffalo"],
                domSignals: ["preview_entity", "preview_program"]
            ),
        ]
    }
}
