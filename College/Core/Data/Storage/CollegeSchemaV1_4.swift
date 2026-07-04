// CollegeSchemaV1_4.swift
// Feature: Core/Data
// Purpose: Schema 1.4 — transfer equivalency + proof records.

import SwiftData

enum CollegeSchemaV1_4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 4, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_3.models + [
            TransferEquivalency.self,
            TransferProofRecord.self,
        ]
    }
}
