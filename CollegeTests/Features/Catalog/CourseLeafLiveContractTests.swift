// CourseLeafLiveContractTests.swift
// Feature: Shared
// Purpose: Shared module — SchoolLiveContract.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Live-site contract tests crawl each CourseLeaf school once, discover every catalog
/// segment from the sitemap, and validate coverage plus shared quality thresholds.
final class CourseLeafLiveContractTests: XCTestCase {
    private static let minQualityRatio = 0.90

    private struct SchoolLiveContract {
        let schoolID: String
        let rootBaseURL: String
    }

    private struct CatalogSegmentContract {
        let id: String
        let displayName: String
        let coursePathPrefixes: [String]
        let programPathPrefixes: [String]
        let minCourses: Int
        let minPrograms: Int
        let minMajors: Int
        let minMinors: Int
        let anchorCourses: [AnchorCourse]
    }

    private struct AnchorCourse {
        let code: String
        let titleContains: String
        let minCredits: Int
    }

    private let schoolContracts: [SchoolLiveContract] = [
        SchoolLiveContract(
            schoolID: "fordham_university",
            rootBaseURL: "https://bulletin.fordham.edu/"
        ),
        SchoolLiveContract(
            schoolID: "carnegie_mellon_university",
            rootBaseURL: "http://coursecatalog.web.cmu.edu/"
        ),
        SchoolLiveContract(
            schoolID: "new_york_university",
            rootBaseURL: "https://bulletins.nyu.edu/"
        )
    ]

    /// Optional anchor checks for high-signal segments (most segments rely on quality ratios only).
    private let segmentAnchorCourses: [String: [AnchorCourse]] = [
        "fordham_university_courses_aast": [
            AnchorCourse(code: "AAST", titleContains: "Asian American", minCredits: 1)
        ],
        "carnegie_mellon_university_schools_colleges_schoolofcomputerscience": [
            AnchorCourse(code: "15-", titleContains: "", minCredits: 0)
        ],
        "carnegie_mellon_university_schools_colleges_collegeofengineering": [
            AnchorCourse(code: "39-109", titleContains: "Grand Challenge", minCredits: 1)
        ],
        "new_york_university_courses_csci_ua": [
            AnchorCourse(code: "CSCI-UA 101", titleContains: "Intro to Computer Science", minCredits: 4),
            AnchorCourse(code: "CSCI-UA 102", titleContains: "Data Structures", minCredits: 4)
        ]
    ]

    func testLiveCatalog_eachCatalogSegment_meetsCoverageAndQualityContracts() async throws {
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
        for school in schoolContracts {
            let discovered = try await CourseLeafCatalogSegmentDiscoverer.discoverSegments(
                baseURL: school.rootBaseURL,
                schoolID: school.schoolID
            )
            XCTAssertFalse(
                discovered.isEmpty,
                "\(school.schoolID): sitemap discovery returned no catalog segments"
            )

            let output = try await CourseLeafEngine.crawlCatalog(
                baseURL: school.rootBaseURL,
                schoolID: school.schoolID
            )

            for segment in discovered {
                let catalog = catalogContract(from: segment)
                let courses = filterByPathPrefixes(
                    output.courses,
                    urlString: { $0.previewDetailURL },
                    prefixes: catalog.coursePathPrefixes
                )
                let programs = filterByPathPrefixes(
                    output.programs,
                    urlString: { $0.url },
                    prefixes: catalog.programPathPrefixes
                )

                if courses.isEmpty && programs.isEmpty {
                    continue
                }

                try assertCatalogSegment(
                    schoolID: school.schoolID,
                    catalog: catalog,
                    courses: courses,
                    programs: programs
                )
            }

            try assertSchoolWideCourseQuality(
                schoolID: school.schoolID,
                courses: output.courses
            )
        }
    }

    private func catalogContract(
        from segment: CourseLeafCatalogSegmentDiscoverer.DiscoveredSegment
    ) -> CatalogSegmentContract {
        let prefix = segment.pathPrefix
        return CatalogSegmentContract(
            id: segment.id,
            displayName: segment.displayName,
            coursePathPrefixes: [prefix],
            programPathPrefixes: [prefix],
            minCourses: segment.minCourses,
            minPrograms: segment.minPrograms,
            minMajors: 0,
            minMinors: 0,
            anchorCourses: segmentAnchorCourses[segment.id] ?? []
        )
    }

    private func assertCatalogSegment(
        schoolID: String,
        catalog: CatalogSegmentContract,
        courses: [CatalogCourse],
        programs: [ScrapedProgram]
    ) throws {
        let label = "\(schoolID)/\(catalog.id) (\(catalog.displayName))"

        let needsCourses = catalog.minCourses > 0
        let needsPrograms = catalog.minPrograms > 0
        if needsCourses && needsPrograms {
            XCTAssertTrue(
                courses.count >= catalog.minCourses || programs.count >= catalog.minPrograms,
                "\(label): expected at least \(catalog.minCourses) courses or \(catalog.minPrograms) programs (got \(courses.count) courses, \(programs.count) programs)"
            )
        } else {
            if needsCourses {
                XCTAssertGreaterThanOrEqual(
                    courses.count,
                    catalog.minCourses,
                    "\(label): expected at least \(catalog.minCourses) courses"
                )
            }
            if needsPrograms {
                XCTAssertGreaterThanOrEqual(
                    programs.count,
                    catalog.minPrograms,
                    "\(label): expected at least \(catalog.minPrograms) programs"
                )
            }
        }

        for anchor in catalog.anchorCourses {
            let match = courses.first { course in
                course.courseCode.localizedCaseInsensitiveContains(anchor.code)
                    && (anchor.titleContains.isEmpty || course.title.localizedCaseInsensitiveContains(anchor.titleContains))
                    && course.credits >= anchor.minCredits
            }
            XCTAssertNotNil(match, "\(label): missing anchor course matching \(anchor.code)")
        }
    }

    private func assertSchoolWideCourseQuality(
        schoolID: String,
        courses: [CatalogCourse]
    ) throws {
        guard !courses.isEmpty else {
            XCTFail("\(schoolID): crawl produced no courses for school-wide quality check")
            return
        }
        let label = "\(schoolID) (all courses)"
        try assertCourseQualityThresholds(label: label, courses: courses)
    }

    private func assertCourseQualityThresholds(
        label: String,
        courses: [CatalogCourse]
    ) throws {
        let distinctTitleRatio = qualityRatio(courses) { course in
            course.title.caseInsensitiveCompare(course.courseCode) != .orderedSame
        }
        XCTAssertGreaterThanOrEqual(
            distinctTitleRatio,
            Self.minQualityRatio,
            "\(label): title quality \(distinctTitleRatio) < \(Self.minQualityRatio)"
        )

        let creditEligible = courses.filter(courseMentionsCreditsInSourceText)
        if !creditEligible.isEmpty {
            let creditsRatio = qualityRatio(creditEligible) { $0.credits > 0 }
            XCTAssertGreaterThanOrEqual(
                creditsRatio,
                Self.minQualityRatio,
                "\(label): credits quality \(creditsRatio) < \(Self.minQualityRatio) (n=\(creditEligible.count))"
            )
        }

        let descriptionRatio = qualityRatio(courses) {
            guard let description = $0.description else { return false }
            return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        XCTAssertGreaterThanOrEqual(
            descriptionRatio,
            Self.minQualityRatio,
            "\(label): description quality \(descriptionRatio) < \(Self.minQualityRatio)"
        )
    }

    private func filterByPathPrefixes<T>(
        _ items: [T],
        urlString: (T) -> String?,
        prefixes: [String]
    ) -> [T] {
        guard !prefixes.isEmpty else { return items }
        return items.filter { item in
            guard let raw = urlString(item)?.lowercased() else { return false }
            return prefixes.contains { raw.contains($0.lowercased()) }
        }
    }

    private func qualityRatio<T>(_ items: [T], predicate: (T) -> Bool) -> Double {
        guard !items.isEmpty else { return 0 }
        let hits = items.filter(predicate).count
        return Double(hits) / Double(items.count)
    }

    private func courseMentionsCreditsInSourceText(_ course: CatalogCourse) -> Bool {
        let text = "\(course.title) \(course.description ?? "")".lowercased()
        return text.contains("credit") || text.contains("unit") || text.contains("point")
    }
}
