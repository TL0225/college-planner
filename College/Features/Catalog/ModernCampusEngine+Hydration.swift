// ModernCampusEngine+Hydration.swift
// Feature: Catalog
// Purpose: Catalog module — ModernCampusEngine+Hydration.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension ModernCampusEngine {
    static func fetchProgramCatalogRequirementSheet(
        baseURL: String,
        catoid: String,
        poid: String
    ) async throws -> ProgramCatalogRequirementSheet {
        _ = (baseURL, catoid, poid)
        throw ScraperError.invalidResponse
    }

    static func mergeCatalogCourseFromPreviewHTML(
        _ html: String,
        skeleton: CatalogCourse,
        baseURL: String
    ) -> CatalogCourse {
        _ = (html, baseURL)
        return skeleton
    }

    static func fetchHTMLPublic(_ urlString: String, politeness: CatalogFetchPoliteness) async throws -> String {
        if let url = URL(string: urlString) {
            await CatalogOriginRobotsThrottle.applyPoliteDelayBeforeFetch(url: url, politeness: politeness)
        }
        return try await fetchHTMLPublic(urlString)
    }
}
