// CourseLeafProgramIndexingTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafProgramIndexingTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafProgramIndexingTests: XCTestCase {
  /// Representative NYU undergraduate program URLs across multiple schools (not just Shanghai / Social Work).
  private let nyuUndergradProgramURLs = [
    "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology-ba/",
    "https://bulletins.nyu.edu/undergraduate/arts-science/programs/computer-science-ba/",
    "https://bulletins.nyu.edu/undergraduate/stern/programs/accounting-bs/",
    "https://bulletins.nyu.edu/undergraduate/engineering/programs/computer-science-bs/",
    "https://bulletins.nyu.edu/undergraduate/gallatin/programs/individuated-major-ba/",
    "https://bulletins.nyu.edu/undergraduate/shanghai/programs/mathematics-bs/",
    "https://bulletins.nyu.edu/undergraduate/social-work/programs/social-work-bs/",
    "https://bulletins.nyu.edu/undergraduate/steinhardt/programs/media-culture-communication-bs/",
  ]

  func testRepresentativeNYUPrograms_matchUndergraduateCatalog() {
    let catalog = CourseLeafCatalogSegmentDiscoverer.OnboardingCatalog(
      id: "new_york_university_undergraduate",
      displayName: "Undergraduate",
      pathPrefixes: ["/undergraduate/"]
    )

    for url in nyuUndergradProgramURLs {
      XCTAssertTrue(
        CourseLeafCatalogSegmentDiscoverer.programMatchesCatalog(url: url, catalog: catalog),
        "Expected \(url) to match undergraduate catalog"
      )
      XCTAssertTrue(
        CourseLeafCatalogSegmentDiscoverer.programURLMatchesCatalogID(
          url,
          catalogID: catalog.id
        )
      )
    }
  }

  func testRepresentativeNYUPrograms_assignDistinctDepartments() {
    let departments = Set(
      nyuUndergradProgramURLs.compactMap { raw -> String? in
        guard let url = URL(string: raw) else { return nil }
        return CourseLeafProgramURLParser.ownership(from: url).department
      }
    )
    XCTAssertGreaterThanOrEqual(departments.count, 5, "Expected multiple department buckets for UI grouping")
  }
}
