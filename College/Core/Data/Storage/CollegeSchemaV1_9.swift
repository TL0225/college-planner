// CollegeSchemaV1_9.swift
// Feature: Core/Data
// Purpose: Schema 1.9 — VaultDocument calendar event link field.

import SwiftData

enum CollegeSchemaV1_9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 9, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1_8.models
    }

    /// `VaultDocument.linkedCalendarEventID` is optional on the shared V1 model class;
    /// lightweight migration from V1_8 is driven by updated property metadata checksums.
    static func assertDistinctFromV1_8() {
        assert(
            versionIdentifier != CollegeSchemaV1_8.versionIdentifier,
            "CollegeSchemaV1_9 must bump schema version beyond V1_8"
        )
    }
}
