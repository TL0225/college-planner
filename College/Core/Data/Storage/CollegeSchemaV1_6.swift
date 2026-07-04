// CollegeSchemaV1_6.swift
// Feature: Core/Data
// Purpose: Schema 1.6 — catalog hierarchy, editions, requirement AST persistence.

import SwiftData

enum CollegeSchemaV1_6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 6, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_4.models + [
            CatalogCollege.self,
            CatalogEdition.self,
        ]
    }
}
