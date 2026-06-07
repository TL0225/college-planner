// CollegeSchemaV1_2.swift
// Feature: Core/Data
// Purpose: Schema 1.2 — catalog entity stable IDs + provenance on Major/CourseCatalog/requirements.
// Data: CollegePersistence / repositories when applicable.

import SwiftData

enum CollegeSchemaV1_2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 2, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1.models
    }
}
