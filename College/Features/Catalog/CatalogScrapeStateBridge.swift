// CatalogScrapeStateBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogScrapeStateBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persists per-catalog scrape completion markers in local store only (Phase 7f).
@MainActor
enum CatalogScrapeStateBridge {
    static func upsertCourseScrapeState(
        universityName: String,
        catoid: String,
        catalogTitle: String?,
        courseCount: Int,
        scrapedAt: Date = .now,
        appDataStore: AppDataStore = .shared
    ) async {
        let trimmedUniversity = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCatoid = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUniversity.isEmpty, !trimmedCatoid.isEmpty else { return }
        guard let repo = appDataStore.catalogRepository else { return }
        guard let active = try? repo.fetchActiveUniversity(),
              active.name.caseInsensitiveCompare(trimmedUniversity) == .orderedSame else {
            return
        }

        do {
            _ = try repo.ensureUniversity(id: active.id, name: trimmedUniversity, isActive: true)
            try repo.upsertCourseScrapeState(
                universityID: active.id,
                catoid: trimmedCatoid,
                catalogTitle: catalogTitle,
                courseCount: courseCount,
                scrapedAt: scrapedAt
            )
            ModelMergeCoalescer.flushNow()
            appDataStore.bumpCatalogDataRevision()
        } catch {
            AppLogger.shared.error("CatalogScrapeStateBridge: scrape state upsert failed: \(error)")
        }
    }
}
