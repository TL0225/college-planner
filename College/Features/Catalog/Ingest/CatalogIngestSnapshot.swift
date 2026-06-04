// CatalogIngestSnapshot.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogIngestSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogIngestSnapshot: Sendable {
    enum Scope: Sendable, Equatable {
        case fullSchool
        case programsOnly
        case requirementsOnly
        case bundleImport
        case partialCourses
    }

    let schoolID: String
    let schoolName: String
    let scope: Scope
    let format: String
    let importedAt: Date
    let courseCount: Int
    let programCount: Int
    let requirementCount: Int
    let policyCount: Int
}

struct CatalogReconcileSummary: Sendable {
    let upserted: Int
    let archived: Int
    let deleted: Int
}
