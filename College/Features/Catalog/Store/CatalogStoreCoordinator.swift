// CatalogStoreCoordinator.swift
// Feature: Catalog
// Purpose: Catalog module — SchoolStoreRecord.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
final class CatalogStoreCoordinator {
    static let shared = CatalogStoreCoordinator()

    struct SchoolStoreRecord: Codable, Sendable {
        let schoolID: String
        let universityID: UUID
        let universityName: String
        let updatedAt: Date
    }

    private let fm = FileManager.default

    private init() {}

    var storesRootDirectory: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent("College/catalog-stores", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var registryURL: URL {
        storesRootDirectory.appendingPathComponent("registry.json")
    }

    func storeDirectory(for schoolID: String) -> URL {
        storesRootDirectory.appendingPathComponent(schoolID, isDirectory: true)
    }

    /// Legacy local store per-school snapshot path (deprecated).
    func storeURL(for schoolID: String) -> URL {
        storeDirectory(for: schoolID).appendingPathComponent("catalog.sqlite")
    }

    /// Active local store catalog store for a school.
    func localStoreStoreURL(for schoolID: String) -> URL {
        CollegeModelContainerFactory.catalogStoreURL(for: schoolID)
    }

    func ensureStoreDirectory(for schoolID: String) throws {
        try fm.createDirectory(at: storeDirectory(for: schoolID), withIntermediateDirectories: true)
    }

    func loadRegistry() -> [SchoolStoreRecord] {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode([SchoolStoreRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    func upsertRegistryRecord(schoolID: String, universityID: UUID, universityName: String) {
        var records = loadRegistry().filter { $0.schoolID != schoolID }
        records.append(
            SchoolStoreRecord(
                schoolID: schoolID,
                universityID: universityID,
                universityName: universityName,
                updatedAt: Date()
            )
        )
        records.sort { $0.schoolID < $1.schoolID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? encoder.encode(records) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    func removeRegistryRecord(schoolID: String) {
        let records = loadRegistry().filter { $0.schoolID != schoolID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? encoder.encode(records) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    func schoolID(for universityName: String) -> String {
        let explicit = CollegePersistence.shared.catalogManifestSchoolID(forUniversityName: universityName)
        let fallback = universityName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return (explicit?.isEmpty == false ? explicit! : fallback)
    }

    private static let universitiesMigrationSchemaKey = "catalog.storeCoordinator.universitiesMigrationSchema"
    private static let universitiesMigrationSchemaVersion = 2

    /// Seeds registry entries from local store catalog universities (one-time per schema version).
    func migrateUniversitiesFromCurrentStoreIfNeeded(persistence: CollegePersistence = .shared) {
        let completedVersion = UserDefaults.standard.integer(forKey: Self.universitiesMigrationSchemaKey)
        guard completedVersion < Self.universitiesMigrationSchemaVersion else { return }
        migrateUniversitiesFromCurrentStore(persistence: persistence)
        UserDefaults.standard.set(
            Self.universitiesMigrationSchemaVersion,
            forKey: Self.universitiesMigrationSchemaKey
        )
    }

    func migrateUniversitiesFromCurrentStore(persistence: CollegePersistence = .shared) {
        guard let repo = persistence.catalogRepository else { return }
        let universities = (try? repo.fetchUniversities()) ?? []
        for university in universities {
            let name = university.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let schoolID = schoolID(for: name)
            upsertRegistryRecord(schoolID: schoolID, universityID: university.id, universityName: name)
        }
    }

    struct StoreDiagnostics: Sendable {
        let schoolID: String
        let sqlitePath: String
        let exists: Bool
        let sizeBytes: Int64
    }

    func diagnostics(for schoolID: String) -> StoreDiagnostics {
        let url = storeURL(for: schoolID)
        let exists = fm.fileExists(atPath: url.path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return StoreDiagnostics(
            schoolID: schoolID,
            sqlitePath: url.path,
            exists: exists,
            sizeBytes: size
        )
    }
}
