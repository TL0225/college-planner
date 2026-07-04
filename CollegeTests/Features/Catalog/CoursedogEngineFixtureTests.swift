// CoursedogEngineFixtureTests.swift
// Feature: Catalog
// Purpose: Offline parsing guarantees for Coursedog program discovery.

import XCTest
@testable import College

final class CoursedogEngineFixtureTests: XCTestCase {
    func testParsePrograms_rutgersFixture_extractsProgramLinks() throws {
        let html = try String(
            contentsOf: TestFixturePaths.url("Coursedog/rutgers_programs_index.html"),
            encoding: .utf8
        )
        let base = URL(string: "https://catalogs.rutgers.edu/")!
        let programs = CoursedogEngine.parsePrograms(from: html, baseURL: base)

        XCTAssertGreaterThanOrEqual(programs.count, 2)
        XCTAssertTrue(programs.contains(where: { $0.name.contains("Computer Science") }))
        XCTAssertTrue(programs.contains(where: { $0.type == "Minor" }))
    }

    func testParsePrograms_ccnyFixture_extractsProgramLinks() throws {
        let html = try String(
            contentsOf: TestFixturePaths.url("Coursedog/ccny_programs_index.html"),
            encoding: .utf8
        )
        let base = URL(string: "https://ccny-undergraduate.catalog.cuny.edu/")!
        let programs = CoursedogEngine.parsePrograms(from: html, baseURL: base)

        XCTAssertGreaterThanOrEqual(programs.count, 5)
        XCTAssertTrue(programs.contains(where: { $0.name.contains("Computer Science") }))
    }

    func testProgramDisplayName_fallsBackToSlug() {
        XCTAssertEqual(
            CoursedogEngine.programDisplayName(
                anchorText: "",
                href: "https://main.catalogs.rutgers.edu/#/programs/computer-science-bs"
            ),
            "Computer Science Bs"
        )
    }

    func testIsCoursedogProgramURL_detectsPathRoutes() {
        XCTAssertTrue(
            CoursedogEngine.isCoursedogProgramURL(
                "https://ccny-undergraduate.catalog.cuny.edu/programs/ANTH-BA"
            )
        )
        XCTAssertTrue(
            CoursedogEngine.isCoursedogProgramURL(
                "https://newbrunswick-undergrad-25-26.catalogs.rutgers.edu/schools/eng/programs-study/aerospace"
            )
        )
        XCTAssertFalse(
            CoursedogEngine.isCoursedogProgramURL(
                "https://newbrunswick-undergrad-25-26.catalogs.rutgers.edu/schools/eng/programs-study/programs/aerospace-engineering"
            )
        )
        XCTAssertFalse(CoursedogEngine.isCoursedogProgramURL("https://ccny-undergraduate.catalog.cuny.edu/programs"))
    }

    func testIsCoursedogProgramURL_detectsHashRoutes() {
        XCTAssertTrue(
            CoursedogEngine.isCoursedogProgramURL(
                "https://catalogs.rutgers.edu/#/programs/computer-science-bs"
            )
        )
        XCTAssertFalse(
            CoursedogEngine.isCoursedogProgramURL(
                "https://catalog.dsu.edu/preview_program.php?catoid=7&poid=123"
            )
        )
    }

    func testProgramDetailLoadPlan_hashRouteUsesCatalogShell() {
        let plan = CoursedogEngine.programDetailLoadPlan(
            programURL: "https://ccny-undergraduate.catalog.cuny.edu/#/programs/computer-science-bs"
        )
        XCTAssertEqual(plan?.loadURL.absoluteString, "https://ccny-undergraduate.catalog.cuny.edu/")
        XCTAssertEqual(plan?.hashRoute, "/programs/computer-science-bs")
    }

    func testProgramDetailLoadPlan_pathRouteLoadsDirectURL() {
        let programURL =
            "https://newbrunswick-undergrad-25-26.catalogs.rutgers.edu/schools/eng/programs-study/programs/aerospace-engineering"
        let plan = CoursedogEngine.programDetailLoadPlan(programURL: programURL)
        XCTAssertEqual(plan?.loadURL.absoluteString, programURL)
        XCTAssertNil(plan?.hashRoute)
    }
}
