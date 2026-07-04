// CollegeSchemaMigrationPlan.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegeSchemaMigrationPlan.
// Data: CollegePersistence / repositories when applicable.

import SwiftData

/// Lightweight migrations:
/// - 1.0 → 1.1 (`FocusBlockRecord`)
/// - 1.1 → 1.3 (career match cache + profile field additions)
///
/// Profile `skillsJSON` / `linksJSON` and Experience `technologies` are optional fields on the
/// shared V1 model classes; they migrate lightweight under the V1_3 schema stamp.
///
/// **Do not register checksum-only stamps** (`CollegeSchemaV1_2`, `CollegeSchemaV1_5`, `CollegeSchemaV1_7`,
/// or any re-export of an earlier model list) in `schemas` or `stages`. Duplicate checksums trigger
/// `NSInvalidArgumentException: Duplicate version checksums detected.` at container open.
/// - 1.2.0 stores migrate via 1.1 → 1.3
/// - 1.5.0 stores migrate via 1.4 → 1.6
enum CollegeSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            CollegeSchemaV1_0.self,
            CollegeSchemaV1.self,
            CollegeSchemaV1_3.self,
            CollegeSchemaV1_4.self,
            CollegeSchemaV1_6.self,
            CollegeSchemaV1_8.self,
            CollegeSchemaV1_9.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_0.self, toVersion: CollegeSchemaV1.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1.self, toVersion: CollegeSchemaV1_3.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_3.self, toVersion: CollegeSchemaV1_4.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_4.self, toVersion: CollegeSchemaV1_6.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_6.self, toVersion: CollegeSchemaV1_8.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_8.self, toVersion: CollegeSchemaV1_9.self),
        ]
    }
}