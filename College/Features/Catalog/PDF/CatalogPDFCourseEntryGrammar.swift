// CatalogPDFCourseEntryGrammar.swift
// Feature: Catalog
// Purpose: Grammar model for adaptive course-description block parsing.

import Foundation

/// How a course code appears at the start of a header line.
enum CatalogPDFHeaderCodeShape: String, Codable, Sendable, CaseIterable {
    /// `AIGB 7290.` (CourseLeaf / Fordham)
    case alphaNumDot
    /// `ACCT 2001` (Brooklyn)
    case alphaNum
    /// `69-097` (CMU)
    case numNum
}

/// Where and how per-course metadata (credits, units, etc.) appears.
enum CatalogPDFMetadataGrammar: String, Codable, Sendable, CaseIterable {
    /// `(3 Credits)` on the header or its immediate continuation.
    case inlineParenthetical
    /// `3 hours; 3 credits` on the line after the header/title block.
    case nextLineHoursCredits
    /// `Fall and Spring: 12 units` on the line after the header/title block.
    case nextLineTermUnits
    /// `Modern Biology 9-10` — units or unit range at end of the header line (CMU science courses).
    case trailingUnitsRange
    // Reserved for future growth: variableCredits, repeatable, passFail, labFee
}

/// Rules for recognizing and splitting a course header into code + title.
struct CatalogPDFHeaderGrammar: Sendable, Equatable {
    let codeShape: CatalogPDFHeaderCodeShape
    /// Line-start regex with capture groups: (1) subject or dept prefix, (2) number OR full code parts.
    let headerPattern: String
    /// Whether the code can appear alone on a line with the title on following lines.
    let allowsSplitCodeLine: Bool
    /// Maximum title-continuation lines before giving up on metadata.
    let maxTitleContinuationLines: Int

    static let builtins: [CatalogPDFHeaderGrammar] = [
        CatalogPDFHeaderGrammar(
            codeShape: .alphaNumDot,
            headerPattern: #"^([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\.\s+(.*)$"#,
            allowsSplitCodeLine: false,
            maxTitleContinuationLines: 3
        ),
        CatalogPDFHeaderGrammar(
            codeShape: .alphaNum,
            headerPattern: #"^([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\s+(.+)$"#,
            allowsSplitCodeLine: false,
            maxTitleContinuationLines: 4
        ),
        CatalogPDFHeaderGrammar(
            codeShape: .numNum,
            headerPattern: #"^(\d{2})-(\d{3})\s+(.*)$"#,
            allowsSplitCodeLine: true,
            maxTitleContinuationLines: 4
        ),
    ]

    static func builtin(for codeShape: CatalogPDFHeaderCodeShape) -> CatalogPDFHeaderGrammar {
        builtins.first { $0.codeShape == codeShape } ?? builtins[0]
    }

    /// Split-only header: code on its own line (`03-121`).
    static var numNumSplitPattern: String {
        #"^(\d{2})-(\d{3})$"#
    }
}

/// Full course-entry grammar: header structure + metadata placement + body rules.
struct CatalogPDFCourseEntryGrammar: Sendable, Equatable {
    let header: CatalogPDFHeaderGrammar
    let metadata: CatalogPDFMetadataGrammar

    var identifier: String {
        "\(header.codeShape.rawValue)+\(metadata.rawValue)"
    }
}

/// Outcome of automatic grammar detection on a course-description section.
struct CatalogPDFCourseFormatDetectionResult: Sendable, Equatable {
    let grammar: CatalogPDFCourseEntryGrammar
    let confidence: Double
    let sampleSize: Int
    /// Candidate grammar identifier -> match count used for scoring.
    let evidence: [String: Int]

    var isHighConfidence: Bool {
        confidence >= CatalogPDFCourseFormatDetector.confidenceThreshold
    }
}

/// Diagnostics emitted by the course extraction stage.
struct CatalogPDFCourseExtractionDiagnostics: Sendable, Equatable {
    let detection: CatalogPDFCourseFormatDetectionResult?
    let usedAdaptiveParser: Bool
    let usedLegacyFallback: Bool
    let lowConfidence: Bool
    let coursesWithCredits: Int
    let coursesWithDescriptions: Int
    let failedHeaderCount: Int
    let topFailureReasons: [String]
}
