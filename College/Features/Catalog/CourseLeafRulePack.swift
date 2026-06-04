// CourseLeafRulePack.swift
// Feature: Catalog
// Purpose: Catalog module — CourseLeafRulePack.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CourseLeafRulePack: Sendable {
    let schoolID: String?
    let coursePagePathHints: [String]
    let programPagePathHints: [String]
    let cdataHTMLPatterns: [String]
    let courseCodePatterns: [String]
    let creditPatterns: [String]
    let majorKeywords: [String]
    let minorKeywords: [String]

    static let `default` = CourseLeafRulePack(
        schoolID: nil,
        coursePagePathHints: ["/course", "/courses", "/course-descriptions"],
        programPagePathHints: ["/program", "/programs", "/degree", "/major", "/minor"],
        cdataHTMLPatterns: ["<!\\[CDATA\\[(.*?)\\]\\]>"],
        courseCodePatterns: ["\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4}[A-Z]?)\\b"],
        creditPatterns: [
            "(\\d+(?:\\.\\d+)?)\\s*(?:credits?|credit\\s*hours?)",
            "(\\d+(?:\\.\\d+)?)\\s*units?"
        ],
        majorKeywords: ["major", "b\\.s", "b\\.a", "bachelor", "undergraduate"],
        minorKeywords: ["minor"]
    )

    static let bySchoolID: [String: CourseLeafRulePack] = [
        "fordham_university": CourseLeafRulePack(
            schoolID: "fordham_university",
            coursePagePathHints: ["/courses", "/course-descriptions", "/bulletin"],
            programPagePathHints: [
                "/programs", "/undergraduate", "/graduate", "/gabelli-graduate",
                "/gsas/", "/gse/", "/major/", "/minor/", "/mba/", "/ms/", "/doctoral/"
            ],
            cdataHTMLPatterns: Self.default.cdataHTMLPatterns,
            courseCodePatterns: Self.default.courseCodePatterns,
            creditPatterns: Self.default.creditPatterns,
            majorKeywords: Self.default.majorKeywords,
            minorKeywords: Self.default.minorKeywords
        ),
        "carnegie_mellon_university": CourseLeafRulePack(
            schoolID: "carnegie_mellon_university",
            coursePagePathHints: ["/course-descriptions", "/courses", "/schools-colleges"],
            programPagePathHints: ["/programs", "/undergraduate", "/graduate", "/schools-colleges"],
            cdataHTMLPatterns: Self.default.cdataHTMLPatterns,
            courseCodePatterns: [
                "\\b([0-9]{2})\\s*[-–]\\s*([0-9]{3}[A-Z]?)\\b",
                "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4}[A-Z]?)\\b"
            ],
            creditPatterns: [
                "(\\d+(?:\\.\\d+)?)\\s*units?",
                "(\\d+(?:\\.\\d+)?)\\s*(?:credits?|credit\\s*hours?)"
            ],
            majorKeywords: Self.default.majorKeywords,
            minorKeywords: Self.default.minorKeywords
        ),
        "new_york_university": CourseLeafRulePack(
            schoolID: "new_york_university",
            coursePagePathHints: ["/courses/", "/course-descriptions"],
            programPagePathHints: ["/program", "/programs", "/degree", "/major", "/minor"],
            cdataHTMLPatterns: Self.default.cdataHTMLPatterns,
            courseCodePatterns: [
                "\\b([A-Z]{2,6}-[A-Z]{2})\\s+([0-9]{2,4}[A-Z]?)\\b",
                "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4}[A-Z]?)\\b"
            ],
            creditPatterns: Self.default.creditPatterns,
            majorKeywords: Self.default.majorKeywords,
            minorKeywords: Self.default.minorKeywords
        )
    ]

    static func forSchoolID(_ schoolID: String) -> CourseLeafRulePack {
        bySchoolID[schoolID] ?? .default
    }
}
