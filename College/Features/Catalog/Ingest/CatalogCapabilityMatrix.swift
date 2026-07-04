// CatalogCapabilityMatrix.swift
// Feature: Catalog
// Purpose: Per-school capability matrix from health + benchmark + readiness (P31).

import Foundation

struct CatalogCapabilityRow: Codable, Sendable, Equatable {
    let schoolID: String
    let tier: String
    let layoutFamily: String?
    let ocrRate: Double?
    let programPrecision: Double?
    let programRecall: Double?
    let requirementPrecision: Double?
    let requirementRecall: Double?
    let auditReadiness: Double?
    let overallQualityScore: Double?
    let notes: [String]
}

enum CatalogCapabilityMatrix {
    static func buildRow(
        schoolID: String,
        health: CatalogPDFHealthReport?,
        evaluation: CatalogEvaluationReport?,
        auditReadiness: Double?,
        layoutProfileID: String? = nil
    ) -> CatalogCapabilityRow {
        let tier = CatalogSchoolTierRegistry.tier(for: schoolID)
        var notes: [String] = []
        if let health {
            if health.estimatedOCRPages > 0 {
                notes.append("ocr_pages:\(health.estimatedOCRPages)")
            }
            if let layoutNote = health.layoutNote, !layoutNote.isEmpty {
                notes.append(layoutNote)
            }
        }
        let ocrRate: Double?
        if let health, health.pageCount > 0 {
            ocrRate = Double(health.estimatedOCRPages) / Double(health.pageCount)
        } else {
            ocrRate = nil
        }
        return CatalogCapabilityRow(
            schoolID: schoolID,
            tier: tier.rawValue,
            layoutFamily: layoutProfileID,
            ocrRate: ocrRate,
            programPrecision: evaluation?.programPrecision,
            programRecall: evaluation?.programRecall,
            requirementPrecision: evaluation?.requirementPrecision,
            requirementRecall: evaluation?.requirementRecall,
            auditReadiness: auditReadiness,
            overallQualityScore: evaluation?.overallQualityScore,
            notes: notes
        )
    }

    static func tsvHeader() -> String {
        "schoolID\ttier\tlayoutFamily\tocrRate\tprogramP\tprogramR\treqP\treqR\tauditReady\tOQS\tnotes"
    }

    static func tsvLine(_ row: CatalogCapabilityRow) -> String {
        func fmt(_ value: Double?) -> String {
            guard let value else { return "" }
            return String(format: "%.3f", value)
        }
        return [
            row.schoolID,
            row.tier,
            row.layoutFamily ?? "",
            fmt(row.ocrRate),
            fmt(row.programPrecision),
            fmt(row.programRecall),
            fmt(row.requirementPrecision),
            fmt(row.requirementRecall),
            fmt(row.auditReadiness),
            fmt(row.overallQualityScore),
            row.notes.joined(separator: ";"),
        ].joined(separator: "\t")
    }
}
