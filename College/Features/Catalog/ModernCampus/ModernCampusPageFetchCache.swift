// ModernCampusPageFetchCache.swift
// Feature: Catalog
// Purpose: Run-scoped HTML cache shared by Modern Campus IR paths.
// Data: CollegePersistence / repositories when applicable.

import Foundation

actor ModernCampusPageFetchCache {
    private var htmlByURL: [String: String] = [:]

    func fetchHTML(
        _ urlString: String,
        politeness: CatalogFetchPoliteness = .interactiveBackground
    ) async throws -> String {
        if let cached = htmlByURL[urlString] {
            return cached
        }
        let html = try await ModernCampusEngine.fetchHTMLPublic(urlString, politeness: politeness)
        htmlByURL[urlString] = html
        return html
    }
}
