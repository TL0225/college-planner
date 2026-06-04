// CourseLeafGoldenFixtureTests.swift
// Feature: Shared
// Purpose: Shared module — Manifest.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

/// Deterministic golden tests: frozen CourseLeaf XML fixtures must parse to exact anchor entities.
final class CourseLeafGoldenFixtureTests: XCTestCase {
    private struct Manifest: Decodable {
        let cases: [GoldenCase]
    }

    private struct GoldenCase: Decodable {
        let id: String
        let schoolID: String
        let fixture: String
        let pageURL: String
        let minCourses: Int?
        let courses: [ExpectedCourse]?
        let programs: [ExpectedProgram]?
    }

    private struct ExpectedCourse: Decodable {
        let courseCode: String
        let title: String
        let credits: Int
        let descriptionContains: String?
    }

    private struct ExpectedProgram: Decodable {
        let name: String?
        let nameContains: String?
        let type: String
    }

    func testGoldenFixtures_matchExpectedCoursesProgramsAndMajorsMinors() throws {
        let manifest = try loadManifest()
        for goldenCase in manifest.cases {
            try assertGoldenCase(goldenCase)
        }
    }

    private func loadManifest() throws -> Manifest {
        let url = try fixtureURL(named: "golden_manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func assertGoldenCase(_ goldenCase: GoldenCase) throws {
        let xmlURL = try fixtureURL(named: goldenCase.fixture)
        let xml = try String(contentsOf: xmlURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<courseleaf"), "\(goldenCase.id): fixture is not CourseLeaf XML")

        guard let pageURL = URL(string: goldenCase.pageURL) else {
            XCTFail("\(goldenCase.id): invalid pageURL \(goldenCase.pageURL)")
            return
        }

        let parsed = CourseLeafEngine.parseCatalogPage(
            xml: xml,
            pageURL: pageURL,
            schoolID: goldenCase.schoolID
        )

        if let minCourses = goldenCase.minCourses {
            XCTAssertGreaterThanOrEqual(
                parsed.courses.count,
                minCourses,
                "\(goldenCase.id): expected at least \(minCourses) courses"
            )
        }

        for expected in goldenCase.courses ?? [] {
            let course = parsed.courses.first {
                $0.courseCode.caseInsensitiveCompare(expected.courseCode) == .orderedSame
            }
            XCTAssertNotNil(course, "\(goldenCase.id): missing course \(expected.courseCode)")
            guard let course else { continue }

            XCTAssertEqual(
                course.title,
                expected.title,
                "\(goldenCase.id): title mismatch for \(expected.courseCode)"
            )
            XCTAssertEqual(
                course.credits,
                expected.credits,
                "\(goldenCase.id): credits mismatch for \(expected.courseCode)"
            )
            XCTAssertNotEqual(
                course.title.caseInsensitiveCompare(course.courseCode),
                .orderedSame,
                "\(goldenCase.id): title should not equal code for \(expected.courseCode)"
            )
            if let snippet = expected.descriptionContains {
                let description = course.description ?? ""
                XCTAssertTrue(
                    description.localizedCaseInsensitiveContains(snippet),
                    "\(goldenCase.id): description for \(expected.courseCode) should contain '\(snippet)'"
                )
            }
        }

        for expected in goldenCase.programs ?? [] {
            let program: ScrapedProgram? = {
                if let exact = expected.name {
                    return parsed.programs.first { $0.name == exact }
                }
                if let contains = expected.nameContains {
                    return parsed.programs.first { $0.name.localizedCaseInsensitiveContains(contains) }
                }
                return parsed.programs.first
            }()
            XCTAssertNotNil(program, "\(goldenCase.id): missing expected program")
            guard let program else { continue }
            XCTAssertEqual(
                program.type,
                expected.type,
                "\(goldenCase.id): program type mismatch for \(program.name)"
            )
        }
    }

    private func fixtureURL(named filename: String) throws -> URL {
        let bundle = Bundle(for: CourseLeafGoldenFixtureTests.self)
        if let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures/CourseLeaf") {
            return url
        }
        return try TestFixturePaths.courseLeafURL(named: filename)
    }
}
