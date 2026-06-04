// CatalogCanonicalIR.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCanonicalIR.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogCanonicalIR: Codable, Sendable {
    struct Provenance: Codable, Sendable {
        let documentURL: String
        let parserVersion: String
        let parserCapabilityVersion: String
        let pageStart: Int?
        let pageEnd: Int?
        let confidence: Double?
    }

    struct Program: Codable, Sendable {
        let name: String
        let type: String
        let department: String?
        let degreeType: String?
        let provenance: Provenance
    }

    struct Course: Codable, Sendable {
        let courseCode: String
        let title: String
        let credits: Double
        let department: String
        let provenance: Provenance
    }

    let schoolID: String
    let generatedAt: Date
    let programs: [Program]
    let courses: [Course]
}
