// CourseLeafCatalogSegmentDiscovererTests.swift
// Feature: Shared
// Purpose: Shared module — CourseLeafCatalogSegmentDiscovererTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class CourseLeafCatalogSegmentDiscovererTests: XCTestCase {
    func testDiscoverSegments_fordham_includesUndergraduateAndCourseDepartments() {
        let urls = [
            "https://bulletin.fordham.edu/undergraduate/accounting/major/",
            "https://bulletin.fordham.edu/courses/aast/",
            "https://bulletin.fordham.edu/gabelli-graduate/mba/",
            "https://bulletin.fordham.edu/undergraduate/academic-policies-procedures/foo/"
        ].compactMap(URL.init(string:))

        let segments = CourseLeafCatalogSegmentDiscoverer.discoverSegments(
            pageURLs: urls,
            schoolID: "fordham_university"
        )

        let prefixes = Set(segments.map(\.pathPrefix))
        XCTAssertTrue(prefixes.contains("/undergraduate/accounting/"))
        XCTAssertTrue(prefixes.contains("/courses/aast/"))
        XCTAssertTrue(prefixes.contains("/gabelli-graduate/mba/"))
        XCTAssertFalse(prefixes.contains(where: { $0.contains("academic-policies") }))

        let aast = segments.first { $0.pathPrefix == "/courses/aast/" }
        XCTAssertEqual(aast?.minCourses, 1)
        XCTAssertEqual(aast?.minPrograms, 0)

        let accounting = segments.first { $0.pathPrefix == "/undergraduate/accounting/" }
        XCTAssertEqual(accounting?.minCourses, 0)
        XCTAssertEqual(accounting?.minPrograms, 1)
    }

    func testDiscoverSegments_nyu_collegeAndCourseSlices() {
        let urls = [
            "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/",
            "https://bulletins.nyu.edu/courses/csci_ua/",
            "https://bulletins.nyu.edu/nyu/policies/foo/"
        ].compactMap(URL.init(string:))

        let segments = CourseLeafCatalogSegmentDiscoverer.discoverSegments(
            pageURLs: urls,
            schoolID: "new_york_university"
        )

        let prefixes = Set(segments.map(\.pathPrefix))
        XCTAssertTrue(prefixes.contains("/undergraduate/arts-science/"))
        XCTAssertTrue(prefixes.contains("/courses/csci_ua/"))
        XCTAssertFalse(prefixes.contains(where: { $0.hasPrefix("/nyu/") }))
    }

    func testOnboardingProgramSegments_excludesCourseOnlyBuckets() {
        let urls = [
            "https://bulletin.fordham.edu/undergraduate/accounting/major/",
            "https://bulletin.fordham.edu/courses/aast/"
        ].compactMap(URL.init(string:))

        let segments = CourseLeafCatalogSegmentDiscoverer.onboardingProgramSegments(
            pageURLs: urls,
            schoolID: "fordham_university"
        )

        let prefixes = Set(segments.map(\.pathPrefix))
        XCTAssertTrue(prefixes.contains("/undergraduate/accounting/"))
        XCTAssertFalse(prefixes.contains("/courses/aast/"))
    }

    func testOnboardingCatalogs_nyu_returnsUndergraduateAndGraduateOnly() {
        let urls = [
            "https://bulletins.nyu.edu/undergraduate/arts-science/programs/anthropology/",
            "https://bulletins.nyu.edu/graduate/arts-science/programs/economics/",
            "https://bulletins.nyu.edu/courses/csci_ua/"
        ].compactMap(URL.init(string:))

        let catalogs = CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
            pageURLs: urls,
            schoolID: "new_york_university"
        )

        XCTAssertEqual(catalogs.map(\.displayName), ["Undergraduate", "Graduate"])
    }

    func testOnboardingCatalogs_fordham_returnsTopLevelSchools() {
        let urls = [
            "https://bulletin.fordham.edu/undergraduate/accounting/major/",
            "https://bulletin.fordham.edu/gabelli-graduate/mba/",
            "https://bulletin.fordham.edu/gsas/english/",
            "https://bulletin.fordham.edu/gse/adv-certificate/",
            "https://bulletin.fordham.edu/gss/msw/",
            "https://bulletin.fordham.edu/pcs-grad/programs/"
        ].compactMap(URL.init(string:))

        let catalogs = CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
            pageURLs: urls,
            schoolID: "fordham_university"
        )

        XCTAssertEqual(catalogs.map(\.displayName), [
            "Undergraduate",
            "Graduate School of Business",
            "Graduate School of Arts and Sciences",
            "Graduate School of Education",
            "Graduate School of Social Service",
            "School of Professional and Continuing Studies"
        ])
    }

    func testOnboardingCatalogs_cmu_returnsSingleUniversityCatalog() {
        let urls = [
            "https://coursecatalog.web.cmu.edu/schools-colleges/schoolofcomputerscience/courses/",
            "https://coursecatalog.web.cmu.edu/intercollegeprograms/bxaintercollege/"
        ].compactMap(URL.init(string:))

        let catalogs = CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
            pageURLs: urls,
            schoolID: "carnegie_mellon_university"
        )

        XCTAssertEqual(catalogs.count, 1)
        XCTAssertEqual(catalogs[0].displayName, "University Catalog")
    }

    func testCatalogDescriptors_mapsOnboardingCatalogIDAndTitle() {
        let catalog = CourseLeafCatalogSegmentDiscoverer.OnboardingCatalog(
            id: "new_york_university_undergraduate",
            displayName: "Undergraduate",
            pathPrefixes: ["/undergraduate/"]
        )
        let descriptors = CourseLeafCatalogSegmentDiscoverer.catalogDescriptors(from: [catalog])
        XCTAssertEqual(descriptors.count, 1)
        XCTAssertEqual(descriptors[0].catoid, catalog.id)
        XCTAssertEqual(descriptors[0].title, catalog.displayName)
    }

    func testDiscoverSegments_cmu_allSchoolsColleges() {
        let urls = [
            "https://coursecatalog.web.cmu.edu/schools-colleges/schoolofcomputerscience/courses/",
            "https://coursecatalog.web.cmu.edu/schools-colleges/collegeofengineering/"
        ].compactMap(URL.init(string:))

        let segments = CourseLeafCatalogSegmentDiscoverer.discoverSegments(
            pageURLs: urls,
            schoolID: "carnegie_mellon_university"
        )

        let prefixes = Set(segments.map(\.pathPrefix))
        XCTAssertTrue(prefixes.contains("/schools-colleges/schoolofcomputerscience/"))
        XCTAssertTrue(prefixes.contains("/schools-colleges/collegeofengineering/"))
    }
}
