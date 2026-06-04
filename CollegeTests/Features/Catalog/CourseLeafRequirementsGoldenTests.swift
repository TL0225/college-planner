// CourseLeafRequirementsGoldenTests.swift
// Feature: Shared
// Purpose: Shared module — GoldenManifest.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafRequirementsGoldenTests: XCTestCase {
    private struct GoldenManifest: Decodable {
        struct Case: Decodable {
            let id: String
            let fixture: String
            let programURL: String
            let schoolID: String
            let expectRequiredCodes: [String]?
            let expectProgramTotal: Int?
            let expectCategoryContains: [String]?
            let expectAbsentCategoryContains: [String]?
        }
        let cases: [Case]
    }

    func testGoldenManifest_allCasesParseFromFixtureXML() throws {
        let manifest = try loadManifest()
        for entry in manifest.cases {
            let xml = try fixtureString(named: entry.fixture)
            let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
                xml,
                programURL: entry.programURL,
                schoolID: entry.schoolID
            )
            XCTAssertFalse(requirements.isEmpty, "\(entry.id): expected non-empty requirements")

            if let codes = entry.expectRequiredCodes {
                let parsed = Set(
                    requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) }
                        .map(Self.normalizeCourseCode)
                )
                for code in codes {
                    XCTAssertTrue(
                        parsed.contains(Self.normalizeCourseCode(code)),
                        "\(entry.id): missing code \(code); have \(parsed.sorted())"
                    )
                }
            }

            if let total = entry.expectProgramTotal {
                let footer = requirements.first { $0.category == "__PROGRAM_TOTAL_CREDITS__" }?.creditsRequired
                XCTAssertEqual(footer, total, "\(entry.id): program total")
            }

            let categories = requirements.map(\.category).joined(separator: " | ")
            if let mustContain = entry.expectCategoryContains {
                for fragment in mustContain {
                    XCTAssertTrue(
                        categories.localizedCaseInsensitiveContains(fragment),
                        "\(entry.id): expected category containing '\(fragment)' in [\(categories)]"
                    )
                }
            }

            if let mustNot = entry.expectAbsentCategoryContains {
                for fragment in mustNot {
                    XCTAssertFalse(
                        categories.localizedCaseInsensitiveContains(fragment),
                        "\(entry.id): should not contain '\(fragment)'"
                    )
                }
            }
        }
    }

    func testGoldenManifest_breakdownProjection() throws {
        let manifest = try loadManifest()
        for entry in manifest.cases {
            let xml = try fixtureString(named: entry.fixture)
            let requirements = try CourseLeafRequirementsParser.parseRequirementsFromFixtureXML(
                xml,
                programURL: entry.programURL,
                schoolID: entry.schoolID
            )
            let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
            XCTAssertFalse(visible.isEmpty, "\(entry.id): breakdown should show categories")
        }
    }

    private func loadManifest() throws -> GoldenManifest {
        let url = try fixtureURL(named: "CourseLeafRequirementsGolden.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoldenManifest.self, from: data)
    }

    private func fixtureString(named filename: String) throws -> String {
        let url = try fixtureURL(named: filename)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func normalizeCourseCode(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func fixtureURL(named filename: String) throws -> URL {
        let bundle = Bundle(for: CourseLeafRequirementsGoldenTests.self)
        if let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures/CourseLeaf") {
            return url
        }
        return try TestFixturePaths.courseLeafURL(named: filename)
    }
}
