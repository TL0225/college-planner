import Foundation// ModernCampusAPI.swift

//

/// Compatibility shim.// Intentionally left as a placeholder.

/////

/// The Modern Campus scraping engine was renamed from `ModernCampusAPI` to `ModernCampusEngine`.// The shared Modern Campus scraping implementation lives in `ModernCampusEngine.swift`.

/// This file intentionally contains *only* this shim so older call sites (if any) keep compiling.// This file exists only to avoid Xcode project reference churn during a rename.
final class ModernCampusAPI {

    typealias SearchTarget = ModernCampusEngine.SearchTarget

    static func scrapeCatalog(baseURL: String) async {
        await ModernCampusEngine.scrapeCatalog(baseURL: baseURL)
    }

    static func normalizeCatalogEntryPointForCaller(_ baseURL: String) -> (normalizedBaseURL: String, catoidHint: String?) {
        ModernCampusEngine.normalizeCatalogEntryPointForCaller(baseURL)
    }

    static func discoverCurrentCatalogID(baseURL: String) async throws -> String {
        try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: baseURL)
    }

    static func discoverSearchLocations(baseURL: String, catoid: String) async throws -> [SearchTarget: String] {
        try await ModernCampusEngine.discoverSearchLocations(baseURL: baseURL, catoid: catoid)
    }

    static func fetchPrograms(baseURL: String, catoid: String, locationID: String) async throws -> [ScrapedProgram] {
        try await ModernCampusEngine.fetchPrograms(baseURL: baseURL, catoid: catoid, locationID: locationID)
    }

    static func fetchDepartments(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
        try await ModernCampusEngine.fetchDepartments(baseURL: baseURL, catoid: catoid)
    }

    static func fetchDepartmentsFromSearch(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
        try await ModernCampusEngine.fetchDepartmentsFromSearch(baseURL: baseURL, catoid: catoid)
    }

    static func fetchDepartmentsFromSidebar(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
        try await ModernCampusEngine.fetchDepartmentsFromSidebar(baseURL: baseURL, catoid: catoid)
    }

    // TODO: Restore these when implementing the full course scraping system
    // static func fetchAllCourses(baseURL: String, catalogID: String? = nil) async throws -> [CatalogCourse] {
    //     try await ModernCampusEngine.fetchAllCourses(baseURL: baseURL, catalogID: catalogID)
    // }

    // static func fetchMajors(
    //     baseURL: String,
    //     catalogID: String,
    //     knownDepartments: [ScrapedDepartment]
    // ) async throws -> [(name: String, degreeLevel: String, degreeType: String?, isMinor: Bool, department: String?, url: String, resolvedDepartment: String?, resolvedCollege: String?, mappingConfidence: Double?, mappingSource: String?)] {
    //     try await ModernCampusEngine.fetchMajors(baseURL: baseURL, catalogID: catalogID, knownDepartments: knownDepartments)
    // }

    // Shared helpers used by per-school scrapers.
    // TODO: Restore these when implementing the full course scraping system
    // static func fetchCoursesFromCourseDescriptionsPage_shared(baseURL: String, catoid: String, navoid: String) async throws -> [CatalogCourse] {
    //     try await ModernCampusEngine.fetchCoursesFromCourseDescriptionsPage_shared(baseURL: baseURL, catoid: catoid, navoid: navoid)
    // }

    // static func parseCoursesFromCourseDescriptionsHTML_shared(_ html: String) -> [CatalogCourse] {
    //     ModernCampusEngine.parseCoursesFromCourseDescriptionsHTML_shared(html)
    // }

    // MARK: - Navigation discovery (tests)

    #if DEBUG
    static func invoke_bestNavoidFromIndex_forTests(
        _ html: String,
        catoid: String,
        intentIsPrograms: Bool
    ) -> (navoid: String, label: String, score: Int)? {
        // NOTE: Keep the test surface small and stable.
        if intentIsPrograms {
            guard let cand = ModernCampusEngine.invoke_bestNavoidFromIndex_forTests(html, catoid: catoid, intent: "programs") else { return nil }
            return (cand.navoid, cand.label, cand.score)
        } else {
            guard let cand = ModernCampusEngine.invoke_bestNavoidFromIndex_forTests(html, catoid: catoid, intent: "orgUnits") else { return nil }
            return (cand.navoid, cand.label, cand.score)
        }
    }
    #endif
}
