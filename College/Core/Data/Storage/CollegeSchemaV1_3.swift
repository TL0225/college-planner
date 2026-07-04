// CollegeSchemaV1_3.swift
// Feature: Core/Data
// Purpose: Schema 1.3 — career resume-job match cache + submission hash pinning.
// Data: CollegePersistence / repositories when applicable.

import SwiftData

enum CollegeSchemaV1_3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 3, 0) }

    static var models: [any PersistentModel.Type] {
        CollegeSchemaV1.models + [
            CareerResumeJobMatch.self,
            CareerResumeJobMatchSnapshot.self,
        ]
    }
}
