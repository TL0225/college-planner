// CatalogLayoutProfileGovernance.swift
// Feature: Catalog
// Purpose: Layout profile registry rules — min schools per profile, per-school overrides.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct SchoolLayoutOverride: Codable, Sendable, Equatable {
    let schoolID: String
    let profileID: String
    let reason: String?
    let updatedAt: Date

    init(
        schoolID: String,
        profileID: String,
        reason: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.schoolID = schoolID
        self.profileID = profileID
        self.reason = reason
        self.updatedAt = updatedAt
    }
}

enum SchoolLayoutOverrideStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogLayoutOverrides", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load(schoolID: String) -> SchoolLayoutOverride? {
        let safe = schoolID.replacingOccurrences(of: "/", with: "_")
        let file = root.appendingPathComponent("\(safe).json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(SchoolLayoutOverride.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ override: SchoolLayoutOverride) {
        let safe = override.schoolID.replacingOccurrences(of: "/", with: "_")
        let file = root.appendingPathComponent("\(safe).json")
        if let data = try? JSONEncoder().encode(override) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

enum CatalogLayoutProfileGovernance {
    static let minSchoolsForNewProfile = 5

    static func canAdoptNewProfile(assigningSchoolIDs: [String]) -> Bool {
        assigningSchoolIDs.count >= minSchoolsForNewProfile
    }

    static func validateNewProfileEntry(_ entry: CatalogLayoutProfileEntry) -> String? {
        guard canAdoptNewProfile(assigningSchoolIDs: entry.schoolIDs) else {
            return "Profile \(entry.id) needs at least \(minSchoolsForNewProfile) schools before registry adoption."
        }
        return nil
    }
}
