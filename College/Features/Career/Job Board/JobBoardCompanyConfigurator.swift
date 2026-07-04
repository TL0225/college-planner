// JobBoardCompanyConfigurator.swift
// Feature: Career / Job Board
// Purpose: Shared configuration path for manual and auto-tracked employers.

import Foundation

@MainActor
enum JobBoardCompanyConfigurator {
    struct Result: Sendable {
        let company: JobBoardCompany
        let created: Bool
    }

    static func configureIfNeeded(
        displayName: String,
        careersURL: String,
        platform: JobBoardPlatform,
        slug: String? = nil,
        enqueueScrape: Bool = true
    ) -> Result? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = careersURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return nil }
        let store = JobBoardCompaniesStore.shared
        let resolvedSlug = slug?.lowercased() ?? JobBoardCompaniesStore.slugify(name)
        if let existing = store.companies.first(where: {
            $0.normalizedSlug == resolvedSlug || $0.careersURL.caseInsensitiveCompare(url) == .orderedSame
        }) {
            return Result(company: existing, created: false)
        }
        store.addCompany(displayName: name, careersURL: url, slug: resolvedSlug, platform: platform)
        guard let added = store.companies.first(where: { $0.normalizedSlug == resolvedSlug }) else { return nil }
        if enqueueScrape {
            Task { await JobBoardSyncCoordinator.shared.scrapeCompany(added) }
        }
        CareerSpotlightIndexer.index(
            employer: name,
            slug: added.normalizedSlug,
            careersURL: url,
            openRoleCount: nil
        )
        return Result(company: added, created: true)
    }

    static func removeTracking(slug: String) {
        let store = JobBoardCompaniesStore.shared
        if let company = store.companies.first(where: { $0.normalizedSlug == slug }) {
            store.removeCompany(id: company.id)
        }
    }

    static func isTracked(slug: String?) -> Bool {
        guard let slug else { return false }
        return JobBoardCompaniesStore.shared.companies.contains { $0.normalizedSlug == slug && $0.enabled }
    }
}
