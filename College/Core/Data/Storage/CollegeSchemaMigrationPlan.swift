// CollegeSchemaMigrationPlan.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegeSchemaMigrationPlan.
// Data: CollegePersistence / repositories when applicable.

import SwiftData

/// Lightweight migrations: 1.0 → 1.1 (`FocusBlockRecord`); 1.1 → 1.2 (catalog stable IDs + provenance).
enum CollegeSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CollegeSchemaV1_0.self, CollegeSchemaV1.self, CollegeSchemaV1_2.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1_0.self, toVersion: CollegeSchemaV1.self),
            MigrationStage.lightweight(fromVersion: CollegeSchemaV1.self, toVersion: CollegeSchemaV1_2.self),
        ]
    }
}