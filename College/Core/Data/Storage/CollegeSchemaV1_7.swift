// CollegeSchemaV1_7.swift
// Feature: Core/Data
// Purpose: Historical schema 1.7 stamp (WorkdayJobPosting ↔ JobApplication @Relationship).
//
// **Not registered in `CollegeSchemaMigrationPlan`.** Re-exporting `CollegeSchemaV1_6.models`
// duplicates the V1_6 checksum. DM-R3 relationship metadata lives on shared V1 model classes
// under the active 1.6.0 migration path.

import SwiftData

enum CollegeSchemaV1_7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 7, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_6.models
    }
}
