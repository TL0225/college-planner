// CollegeSchemaV1_2.swift
// Feature: Core/Data
// Purpose: Historical schema 1.2 stamp (catalog provenance release).
// Data: CollegePersistence / repositories when applicable.
//
// **Not registered in `CollegeSchemaMigrationPlan`.** Re-exporting `CollegeSchemaV1.models`
// duplicates the V1_1 checksum and crashes SwiftData staged migration setup. Stores stamped
// 1.2.0 are schema-identical to 1.1.0 and use the V1_1 → V1_3 migration path.

import SwiftData

enum CollegeSchemaV1_2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1.models
    }
}
