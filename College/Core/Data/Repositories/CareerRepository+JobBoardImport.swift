// CareerRepository+JobBoardImport.swift
// Feature: Core/Data
// Purpose: Import scraped listings into SwiftData job-board postings.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

struct JobBoardListImportStats: Equatable, Sendable {
    var inserted: Int = 0
    var updated: Int = 0
    var unchanged: Int = 0
}

/// Accumulates seen listing paths across paginated scrapes and defers removal until finalize.
@MainActor
final class JobBoardListImportSession {
    fileprivate let repo: CareerRepository
    fileprivate let company: JobBoardCompany
    fileprivate let slug: String
    fileprivate let platformRaw: String
    fileprivate let workdayBoard: String?
    fileprivate(set) var seenPaths = Set<String>()
    private var finalized = false

    fileprivate init(repo: CareerRepository, company: JobBoardCompany) {
        self.repo = repo
        self.company = company
        slug = company.normalizedSlug
        platformRaw = company.platform.rawValue
        workdayBoard = company.platform == .workday
            ? WorkdayScraper.deriveAPIContext(careersURLString: company.careersURL)?.board
            : nil
    }

    @discardableResult
    func mergePage(_ listings: [ScrapedJobListing]) throws -> JobBoardListImportStats {
        guard !finalized else { return JobBoardListImportStats() }
        var paths = seenPaths
        let stats = try JobBoardListImportWriter.mergePage(
            context: repo.context,
            company: company,
            listings: listings,
            seenPaths: &paths
        )
        seenPaths = paths
        try repo.context.save()
        return stats
    }

    @discardableResult
    func finalizeRemovals() throws -> Int {
        guard !finalized else { return seenPaths.count }
        finalized = true
        let count = try JobBoardListImportWriter.finalizeRemovals(
            context: repo.context,
            company: company,
            seenPaths: seenPaths
        )
        try repo.context.save()
        CollegePersistence.shared.bumpCareerRevision()
        return count
    }
}

extension CareerRepository {
    func beginJobBoardListImport(company: JobBoardCompany) -> JobBoardListImportSession {
        JobBoardListImportSession(repo: self, company: company)
    }

    /// local store-only job board list import (Phase 7f). Replaces local store `applyListings`.
    @discardableResult
    func applyJobBoardListings(
        company: JobBoardCompany,
        listings: [ScrapedJobListing]
    ) throws -> Int {
        let session = beginJobBoardListImport(company: company)
        _ = try session.mergePage(listings)
        return try session.finalizeRemovals()
    }

    /// Refreshes freshness timestamps without re-importing listing fields (quick-sync path).
    func touchActiveJobBoardPostings(companySlug: String) throws {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return }
        let now = Date()
        let postings = try fetchCompanyPostings(companySlug: slug)
        for posting in postings where posting.isActive {
            posting.lastSeenAt = now
            posting.lastScrapedAt = now
        }
        ModelMergeCoalescer.scheduleSave(context)
        ModelMergeCoalescer.flushNow()
        CollegePersistence.shared.bumpCareerRevision()
    }

    fileprivate func applyScrapedListingFields(
        posting: JobBoardPosting,
        job: ScrapedJobListing,
        company: JobBoardCompany,
        path: String,
        platformRaw: String,
        listingHash: String
    ) {
        posting.companySlug = company.normalizedSlug
        posting.companyDisplayName = company.displayName
        posting.platform = platformRaw
        posting.externalPath = path
        posting.externalId = job.externalId
        posting.title = job.title
        let displayLocation = JobBoardPostingParsing.displayLocation(
            listText: job.locationText,
            externalPath: path
        )
        posting.locationText = displayLocation
        posting.locationsFilterText = JobBoardPostingParsing.joinFilterLocations(
            JobBoardPostingParsing.resolvedFilterLocations(
                listText: job.locationText,
                externalPath: path,
                detailPrimary: nil,
                detailAdditional: nil
            )
        )
        posting.postedOnText = job.postedOn
        posting.postedAt = JobBoardPostingParsing.parsePostedOn(job.postedOn) ?? posting.postedAt
        if let jobType = job.jobTypeText, !jobType.isEmpty { posting.jobTypeText = jobType }
        if let timeType = job.timeType, !timeType.isEmpty { posting.timeType = timeType }
        posting.listingHash = listingHash
        posting.applyURLString = JobBoardURLValidation.normalizedApplyURLString(job.applyURLString)
    }

    fileprivate func fetchOrCreatePosting(companySlug: String, externalPath: String) throws -> JobBoardPosting {
        if let existing = try fetchPosting(companySlug: companySlug, externalPath: externalPath) {
            return existing
        }
        let posting = JobBoardPosting(
            id: UUID(),
            companySlug: companySlug,
            externalId: externalPath,
            isActive: true
        )
        posting.externalPath = externalPath
        context.insert(posting)
        return posting
    }

    fileprivate func deactivateMissingPostings(
        companySlug: String,
        keeping seenPaths: Set<String>,
        platform: JobBoardPlatform,
        workdayBoard: String?
    ) throws {
        let active = try fetchCompanyPostings(companySlug: companySlug)
        for posting in active where posting.isActive {
            let rawPath = posting.externalPath ?? ""
            let path = normalizedListingPath(
                rawPath,
                platform: platform,
                workdayBoard: workdayBoard
            )
            if !seenPaths.contains(path) {
                posting.isActive = false
            }
        }
    }

    fileprivate func normalizedListingPath(
        _ raw: String,
        platform: JobBoardPlatform,
        workdayBoard: String?
    ) -> String {
        switch platform {
        case .workday:
            return WorkdayScraper.normalizeListingExternalPath(raw, board: workdayBoard)
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
