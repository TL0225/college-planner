// CatalogNavigationFlowTests.swift
// Snow Leopard flow #3: catalog course selection stable across fetch.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CatalogNavigationFlowTests: PersistenceTestCase {
    override var includesCatalog: Bool { true }

    func testCourseSelectionStableAfterRefetch() throws {
        let ctx = profileContext!
        let university = University(name: "Test U", isActive: true)
        ctx.insert(university)
        let course = CourseCatalog(
            courseCode: "CSE 101",
            title: "Intro",
            credits: 3,
            isHydrated: true,
            lastUpdated: .now,
            isArchived: false
        )
        course.university = university
        ctx.insert(course)
        try ctx.save()

        let repo = CatalogRepository(context: ctx)
        let first = try repo.fetchCatalogCourse(id: course.id)
        let second = try repo.fetchCatalogCourse(id: course.id)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<CourseCatalog>()), 1)
    }
}
