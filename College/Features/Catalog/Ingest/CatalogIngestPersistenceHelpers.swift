// CatalogIngestPersistenceHelpers.swift
// Feature: Catalog
// Purpose: Shared identity resolution + provenance encoding for catalog ingest adapters.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
enum CatalogIngestPersistenceHelpers {
    static func loadMergedIdentities(
        repo: CatalogRepository,
        universityID: UUID,
        schoolID: String,
        catalogVersionID: String
    ) throws -> [CatalogEntityIdentity] {
        let fromStore = CatalogEntityIdentityStore.load(schoolID: schoolID, catalogVersionID: catalogVersionID)
        let fromDB = try repo.loadStoredEntityIdentities(
            universityID: universityID,
            catalogVersionID: catalogVersionID
        )
        return CatalogEntityIdentityStore.merge(persisted: fromDB, stored: fromStore)
    }

    static func encodeProvenanceJSON(_ provenance: CatalogProvenance) -> String? {
        guard let data = try? JSONEncoder().encode(provenance) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func resolveProgramStableID(
        program: ScrapedProgram,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> (stableID: UUID, identity: CatalogEntityIdentity) {
        let identity = CatalogEntityIdentityMatcher.resolveProgramIdentity(
            url: program.url,
            name: program.name,
            type: program.type,
            catalogVersionID: catalogVersionID,
            existing: existing
        )
        return (identity.stableID, identity)
    }

    static func resolveCourseStableID(
        courseCode: String,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> (stableID: UUID, identity: CatalogEntityIdentity) {
        let identity = CatalogEntityIdentityMatcher.resolveCourseIdentity(
            courseCode: courseCode,
            catalogVersionID: catalogVersionID,
            existing: existing
        )
        return (identity.stableID, identity)
    }

    static func persistIdentities(
        _ identities: [CatalogEntityIdentity],
        schoolID: String,
        catalogVersionID: String
    ) {
        CatalogEntityIdentityStore.save(identities, schoolID: schoolID, catalogVersionID: catalogVersionID)
    }
}
