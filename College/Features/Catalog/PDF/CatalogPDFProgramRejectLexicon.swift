// CatalogPDFProgramRejectLexicon.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFProgramRejectLexicon.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Hard-negative terms for program block classification (policy/procedure prose masquerading as degrees).
enum CatalogPDFProgramRejectLexicon {
    static let negativeSubstrings: [String] = [
    "ferpa", "tuition", "refund", "grievance", "accommodation", "financial aid",
    "admission", "appeal", "procedure", "withdrawal", "grade appeal", "ecsi",
    "payment", "amount due", "step one", "step two", "step three", "step four",
    "must be submitted", "students must", "you must", "please contact",
    "office of", "registrar", "bursar", "copyright", "disclaimer",
    "privacy", "ferpa", "veteran", "veterans", "military", "vaccination",
    "immunization", "housing", "meal plan", "parking", "library hours",
    "academic calendar", "holiday", "commencement", "transcript request",
    "ferpa rights", "title ix", "clery", "accessibility", "disability services",
    "student conduct", "disciplinary", "probation", "suspension", "expulsion",
    "credit card", "check or money", "wire transfer", "installment",
    "late fee", "past due", "balance due", "payment plan",
    ]

    static func matchesNegative(_ text: String) -> [String] {
        let lower = text.lowercased()
        return negativeSubstrings.filter { lower.contains($0) }
    }

    static func hasStrongNegative(_ text: String) -> Bool {
        !matchesNegative(text).isEmpty
    }
}
