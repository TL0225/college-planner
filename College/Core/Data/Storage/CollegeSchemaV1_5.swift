// CollegeSchemaV1_5.swift
// Feature: Core/Data
// Purpose: Historical schema 1.5 stamp (catalog confidence / parser metadata fields).
//
// **Not registered in `CollegeSchemaMigrationPlan`.** Re-exporting `CollegeSchemaV1_4.models`
// duplicates the V1_4 checksum and crashes staged migration setup. Stores stamped 1.5.0 are
// schema-identical to 1.4.0 and migrate via the 1.4 → 1.6 stage.

import SwiftData

enum CollegeSchemaV1_5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 5, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_4.models
    }
}
