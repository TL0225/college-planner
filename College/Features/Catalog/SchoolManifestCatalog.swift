// SchoolManifestCatalog.swift
// Feature: Catalog
// Purpose: Catalog module — SchoolManifestCatalog.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Canonical school list shipped as `schools.json` in the app bundle.
///
/// This file uses the same schema as `college-planner-data/manifests/schools.json`.
/// Copy `College/Catalog/schools.json` into that repo when publishing new schools.
enum SchoolManifestCatalog {
    private static let resourceName = "schools"

    /// Schools from the bundled `schools.json` (offline baseline).
    static func bundled() -> [SchoolManifest] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            assertionFailure("Missing bundled schools.json in app resources")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SchoolManifest].self, from: data)
        } catch {
            assertionFailure("Failed to decode bundled schools.json: \(error)")
            return []
        }
    }

    /// Bundled schools first; GitHub `schools.json` overrides matching ids and adds new entries.
    static func resolved(mergingRemote remote: [SchoolManifest]) -> [SchoolManifest] {
        var byID: [String: SchoolManifest] = [:]
        byID.reserveCapacity(bundled().count + remote.count)
        for school in bundled() {
            byID[school.id] = school
        }
        for school in remote {
            byID[school.id] = school
        }
        return byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Path to the bundled file in the repo (for docs / export workflows).
    static var bundledJSONRepoPath: String { "College/Catalog/schools.json" }

    static var githubManifestPath: String { "manifests/schools.json" }
}

/// Backward-compatible alias; prefer `SchoolManifestCatalog`.
enum BundledSchoolManifests {
    static var supplemental: [SchoolManifest] { SchoolManifestCatalog.bundled() }

    static func merging(into remote: [SchoolManifest]) -> [SchoolManifest] {
        SchoolManifestCatalog.resolved(mergingRemote: remote)
    }
}

/// Shared rules for school pickers (onboarding, Edit Profile academic profile, etc.).
enum SchoolManifestSelection {
    static func isScraperBacked(_ school: SchoolManifest) -> Bool {
        let catalogURL = (school.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else { return false }
        let format = school.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return format == "acalog"
            || format == "banner"
            || format == "custom"
            || format == "moderncampus"
            || format == "courseleaf"
            || format == "coursedog"
    }

    static func scraperBackedNames(from schools: [SchoolManifest]) -> [String] {
        Array(Set(schools
            .filter(isScraperBacked)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Resolved `schools.json` entries plus imported catalog names and the current selection.
    static func universityPickerNames(
        manifests: [SchoolManifest],
        importedCatalogNames: [String],
        preserving currentSelection: String?
    ) -> [String] {
        var names = Set(scraperBackedNames(from: manifests))
        for imported in importedCatalogNames {
            let trimmed = imported.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            names.insert(trimmed)
        }
        if let current = currentSelection?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty {
            names.insert(current)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Picker names from bundled + optional remote merge (canonical school menu list).
    static func universityPickerNames(
        remoteManifests: [SchoolManifest] = [],
        importedCatalogNames: [String] = [],
        preserving currentSelection: String? = nil
    ) -> [String] {
        universityPickerNames(
            manifests: SchoolManifestCatalog.resolved(mergingRemote: remoteManifests),
            importedCatalogNames: importedCatalogNames,
            preserving: currentSelection
        )
    }
}
