// CourseLeafProfileConfig.swift
// Feature: Catalog
// Purpose: Layout-profile extraction config (path hints, code/credit patterns) for CourseLeaf IR.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CourseLeafProfileConfig: Sendable {
    let coursePagePathHints: [String]
    let programPagePathHints: [String]
    let cdataHTMLPatterns: [String]
    let courseCodePatterns: [String]
    let creditPatterns: [String]
    let majorKeywords: [String]
    let minorKeywords: [String]

    init(
        coursePagePathHints: [String],
        programPagePathHints: [String],
        cdataHTMLPatterns: [String],
        courseCodePatterns: [String],
        creditPatterns: [String],
        majorKeywords: [String],
        minorKeywords: [String]
    ) {
        self.coursePagePathHints = coursePagePathHints
        self.programPagePathHints = programPagePathHints
        self.cdataHTMLPatterns = cdataHTMLPatterns
        self.courseCodePatterns = courseCodePatterns
        self.creditPatterns = creditPatterns
        self.majorKeywords = majorKeywords
        self.minorKeywords = minorKeywords
    }

    private static let sharedDefault = CourseLeafProfileConfig(
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

    static func config(for profileID: CourseLeafLayoutProfileID, schoolID: String? = nil) -> CourseLeafProfileConfig {
        _ = schoolID
        switch profileID {
        case .profileA:
            return CourseLeafProfileConfig(
                coursePagePathHints: ["/courses/", "/course-descriptions"],
                programPagePathHints: sharedDefault.programPagePathHints,
                cdataHTMLPatterns: sharedDefault.cdataHTMLPatterns,
                courseCodePatterns: [
                    "\\b([A-Z]{2,6}-[A-Z]{2})\\s+([0-9]{2,4}[A-Z]?)\\b",
                    "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4}[A-Z]?)\\b"
                ],
                creditPatterns: sharedDefault.creditPatterns,
                majorKeywords: sharedDefault.majorKeywords,
                minorKeywords: sharedDefault.minorKeywords
            )
        case .profileB:
            return CourseLeafProfileConfig(
                coursePagePathHints: ["/courses", "/course-descriptions", "/bulletin"],
                programPagePathHints: [
                    "/programs", "/undergraduate", "/graduate", "/gabelli-graduate",
                    "/gsas/", "/gse/", "/major/", "/minor/", "/mba/", "/ms/", "/doctoral/"
                ],
                cdataHTMLPatterns: sharedDefault.cdataHTMLPatterns,
                courseCodePatterns: sharedDefault.courseCodePatterns,
                creditPatterns: sharedDefault.creditPatterns,
                majorKeywords: sharedDefault.majorKeywords,
                minorKeywords: sharedDefault.minorKeywords
            )
        case .profileC:
            return CourseLeafProfileConfig(
                coursePagePathHints: ["/course-descriptions", "/courses", "/schools-colleges"],
                programPagePathHints: ["/programs", "/undergraduate", "/graduate", "/schools-colleges"],
                cdataHTMLPatterns: sharedDefault.cdataHTMLPatterns,
                courseCodePatterns: [
                    "\\b([0-9]{2})\\s*[-–]\\s*([0-9]{3}[A-Z]?)\\b",
                    "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4}[A-Z]?)\\b"
                ],
                creditPatterns: [
                    "(\\d+(?:\\.\\d+)?)\\s*units?",
                    "(\\d+(?:\\.\\d+)?)\\s*(?:credits?|credit\\s*hours?)"
                ],
                majorKeywords: sharedDefault.majorKeywords,
                minorKeywords: sharedDefault.minorKeywords
            )
        case .profileDefault:
            return sharedDefault
        }
    }

}
