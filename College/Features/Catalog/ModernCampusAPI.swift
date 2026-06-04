// ModernCampusAPI.swift
// Feature: Catalog
// Purpose: Catalog module — ModernCampusAPI.
// Data: CollegePersistence / repositories when applicable.

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

    // Backwards-compat: the engine exposes a robots-compliant course crawler for ModernCampus catalogs.
    static func fetchAllCourses(baseURL: String, catoid: String) async throws -> [CatalogCourse] {
        try await ModernCampusEngine.fetchAllCourses(baseURL: baseURL, catoid: catoid)
    }

    // MARK: - Navigation discovery (tests)

    #if DEBUG || COLLEGE_TEST_HOOKS
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
