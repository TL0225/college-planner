// CatalogMultiParserHarness.swift
// Feature: Catalog
// Purpose: Run multiple parsers on the same PDF and pick winner by OQS (P26).

import Foundation

struct CatalogParserCandidateResult: Sendable, Equatable {
    let parserID: String
    let programs: Int
    let courses: Int
    let requirements: Int
    let evaluation: CatalogEvaluationReport
}

enum CatalogMultiParserHarness {
    static func pickWinner(_ candidates: [CatalogParserCandidateResult]) -> CatalogParserCandidateResult? {
        candidates.max { lhs, rhs in
            if lhs.evaluation.overallQualityScore != rhs.evaluation.overallQualityScore {
                return lhs.evaluation.overallQualityScore < rhs.evaluation.overallQualityScore
            }
            if lhs.requirements != rhs.requirements {
                return lhs.requirements < rhs.requirements
            }
            return lhs.programs < rhs.programs
        }
    }

    static func evaluateOutput(
        parserID: String,
        schoolID: String,
        catalogVersionID: String,
        output: CatalogPDFIngestOutput
    ) -> CatalogParserCandidateResult {
        let evaluation = CatalogEvaluationFramework.score(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            programsFound: output.programs.count,
            coursesFound: output.courses.count,
            requirementsFound: output.requirements.count,
            benchmarkPrecision: nil,
            benchmarkRecall: nil,
            requirementPrecision: nil,
            requirementRecall: nil,
            fallbackRate: output.courseExtractionDiagnostics?.usedLegacyFallback == true ? 1 : 0,
            rawPreserved: true
        )
        return CatalogParserCandidateResult(
            parserID: parserID,
            programs: output.programs.count,
            courses: output.courses.count,
            requirements: output.requirements.count,
            evaluation: evaluation
        )
    }
}
