// CollegeSchemaV1_8.swift
// Feature: Core/Data
// Purpose: Schema 1.8 — Career Apply Profile preferences model.

import SwiftData

enum CollegeSchemaV1_8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 8, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_6.models + [
            CareerApplicationPreferences.self,
        ]
    }

    /// Guard against checksum-only stamps that crash staged migration (`Duplicate version checksums across stages`).
    static func assertDistinctFromV1_6() {
        let v6 = Set(CollegeSchemaV1_6.models.map { ObjectIdentifier($0) })
        let v8 = Set(models.map { ObjectIdentifier($0) })
        assert(v8.isStrictSuperset(of: v6), "CollegeSchemaV1_8 must add models beyond V1_6")
    }
}
