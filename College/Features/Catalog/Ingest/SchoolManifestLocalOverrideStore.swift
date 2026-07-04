// SchoolManifestLocalOverrideStore.swift
// Feature: Catalog
// Purpose: Persist probe-derived catalog_format overrides (bundled schools.json stays read-only).

import Foundation

struct SchoolManifestFormatOverride: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogFormat: String
    let detectedAt: Date
    let confidence: Double
    let evidence: [String]
}

enum SchoolManifestLocalOverrideStore {
    private static let fileName = "school_manifest_format_overrides.json"

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("College", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func loadAll() -> [String: SchoolManifestFormatOverride] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([SchoolManifestFormatOverride].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.schoolID, $0) })
    }

    static func override(for schoolID: String) -> SchoolManifestFormatOverride? {
        loadAll()[schoolID]
    }

    static func save(_ override: SchoolManifestFormatOverride) {
        var all = loadAll()
        all[override.schoolID] = override
        persist(Array(all.values))
    }

    static func remove(schoolID: String) {
        var all = loadAll()
        all.removeValue(forKey: schoolID)
        persist(Array(all.values))
    }

    private static func persist(_ overrides: [SchoolManifestFormatOverride]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overrides) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

extension SchoolManifestCatalog {
    /// Bundled → remote GitHub cache → local format override (override wins for `catalog_format` only).
    static func effectiveManifest(_ manifest: SchoolManifest) -> SchoolManifest {
        guard let override = SchoolManifestLocalOverrideStore.override(for: manifest.id) else {
            return manifest
        }
        return manifest.withCatalogFormat(override.catalogFormat)
    }

    static func resolvedApplyingOverrides(mergingRemote remote: [SchoolManifest]) -> [SchoolManifest] {
        resolved(mergingRemote: remote).map { effectiveManifest($0) }
    }
}

extension SchoolManifest {
    func withCatalogFormat(_ format: String) -> SchoolManifest {
        SchoolManifest(
            id: id,
            name: name,
            shortName: shortName,
            unitID: unitID,
            opeID: opeID,
            profileURL: profileURL,
            catalogURL: catalogURL,
            academicCalendarURL: academicCalendarURL,
            timeZoneID: timeZoneID,
            countryCode: countryCode,
            stateCode: stateCode,
            officialWebsiteURL: officialWebsiteURL,
            financialAidURL: financialAidURL,
            registrarURL: registrarURL,
            stateAidAgencyURL: stateAidAgencyURL,
            catalogFormat: format,
            lastUpdated: lastUpdated,
            coursesCount: coursesCount,
            verified: verified,
            transferAggregatorSupported: transferAggregatorSupported,
            assistInstitutionID: assistInstitutionID,
            tesPublicViewURL: tesPublicViewURL,
            bannerArticulationBaseURL: bannerArticulationBaseURL,
            bannerGeneration: bannerGeneration
        )
    }
}
