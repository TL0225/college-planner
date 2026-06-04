// CollegeSchemaMigrationPlan.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegeSchemaMigrationPlan.
// Data: CollegePersistence / repositories when applicable.

import SwiftData

/// Lightweight migration from schema 1.0 → 1.1 (adds `FocusBlockRecord`).
enum CollegeSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CollegeSchemaV1_0.self, CollegeSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: CollegeSchemaV1_0.self, toVersion: CollegeSchemaV1.self)]
    }
}