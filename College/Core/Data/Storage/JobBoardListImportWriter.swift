// JobBoardListImportWriter.swift
// Feature: Core/Data
// Purpose: Off-main SwiftData writes for paginated job-board list import.

import Foundation
import SwiftData

/// Sendable session snapshot for paginated imports (lives on `CollegePersistence` during scrape).
struct JobBoardListImportSessionState: Sendable {
    var company: JobBoardCompany
    var seenPaths: Set<String> = []
    var finalized = false
}

enum JobBoardListImportWriter {
    @discardableResult
    static func mergePage(
        context: ModelContext,
        company: JobBoardCompany,
        listings: [ScrapedJobListing],
        seenPaths: inout Set<String>
    ) throws -> JobBoardListImportStats {
        let slug = company.normalizedSlug
        let platformRaw = company.platform.rawValue
        let workdayBoard = company.platform == .workday
            ? WorkdayScraper.deriveAPIContext(careersURLString: company.careersURL)?.board
            : nil
        let now = Date()

        var postingByPath = try prefetchPostingsByPath(context: context, companySlug: slug)
        var stats = JobBoardListImportStats()

        for job in listings {
            let path = normalizedListingPath(
                job.externalPath,
                platform: company.platform,
                workdayBoard: workdayBoard
            )
            guard !path.isEmpty else { continue }
            seenPaths.insert(path)

            let posting = postingByPath[path] ?? insertPosting(
                context: context,
                companySlug: slug,
                externalPath: path,
                cache: &postingByPath
            )

            let newHash = job.listingHash ?? JobListingHash.compute(title: job.title, locationsText: job.locationText)
            let isNewPosting = posting.firstSeenAt == nil
            let hashChanged = posting.listingHash != nil && posting.listingHash != newHash

            posting.lastSeenAt = now
            posting.lastScrapedAt = now
            posting.isActive = true
            posting.closedAt = nil

            if isNewPosting {
                posting.firstSeenAt = now
                stats.inserted += 1
            } else if hashChanged {
                posting.detailScrapedAt = nil
                stats.updated += 1
            } else {
                stats.unchanged += 1
                continue
            }

            applyScrapedListingFields(
                posting: posting,
                job: job,
                company: company,
                path: path,
                platformRaw: platformRaw,
                listingHash: newHash
            )
        }

        return stats
    }

    @discardableResult
    static func finalizeRemovals(
        context: ModelContext,
        company: JobBoardCompany,
        seenPaths: Set<String>
    ) throws -> Int {
        let slug = company.normalizedSlug
        let workdayBoard = company.platform == .workday
            ? WorkdayScraper.deriveAPIContext(careersURLString: company.careersURL)?.board
            : nil
        guard !seenPaths.isEmpty else { return 0 }

        let active = try fetchCompanyPostings(context: context, companySlug: slug)
        for posting in active where posting.isActive {
            let rawPath = posting.externalPath ?? ""
            let path = normalizedListingPath(
                rawPath,
                platform: company.platform,
                workdayBoard: workdayBoard
            )
            if !seenPaths.contains(path) {
                posting.isActive = false
            }
        }
        return seenPaths.count
    }

    // MARK: - Fetch helpers

    private static func prefetchPostingsByPath(
        context: ModelContext,
        companySlug: String
    ) throws -> [String: JobBoardPosting] {
        let postings = try fetchCompanyPostings(context: context, companySlug: companySlug)
        var byPath: [String: JobBoardPosting] = [:]
        byPath.reserveCapacity(postings.count)
        for posting in postings {
            if let path = posting.externalPath, !path.isEmpty {
                byPath[path] = posting
            }
        }
        return byPath
    }

    private static func fetchCompanyPostings(
        context: ModelContext,
        companySlug: String
    ) throws -> [JobBoardPosting] {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return [] }
        var descriptor = FetchDescriptor<JobBoardPosting>(
            predicate: #Predicate { posting in
                posting.companySlug == slug
            }
        )
        descriptor.fetchLimit = 5000
        return try context.fetch(descriptor)
    }

    private static func insertPosting(
        context: ModelContext,
        companySlug: String,
        externalPath: String,
        cache: inout [String: JobBoardPosting]
    ) -> JobBoardPosting {
        let posting = JobBoardPosting(
            id: UUID(),
            companySlug: companySlug,
            externalId: externalPath,
            isActive: true
        )
        posting.externalPath = externalPath
        context.insert(posting)
        cache[externalPath] = posting
        return posting
    }

    private static func normalizedListingPath(
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

    private static func applyScrapedListingFields(
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
}
