// CareerRepository+WorkdayImport.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerRepository+WorkdayImport.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CareerRepository {
    /// local store-only job board list import (Phase 7f). Replaces local store `applyListings`.
    @discardableResult
    func applyJobBoardListings(
        company: WorkdayCompanyConfigEntry,
        listings: [ScrapedJobListing]
    ) throws -> Int {
        let slug = company.normalizedSlug
        let now = Date()
        var seenPaths = Set<String>()
        let platformRaw = company.platform.rawValue

        for job in listings {
            let path = job.externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            seenPaths.insert(path)

            let posting = try fetchOrCreatePosting(companySlug: slug, externalPath: path)
            let newHash = job.listingHash ?? WorkdayListingHash.compute(title: job.title, locationsText: job.locationText)
            let isNewPosting = posting.firstSeenAt == nil
            let hashChanged = posting.listingHash != nil && posting.listingHash != newHash

            posting.lastSeenAt = now
            posting.lastScrapedAt = now
            posting.isActive = true
            posting.closedAt = nil

            if isNewPosting {
                posting.firstSeenAt = now
            } else if hashChanged {
                posting.detailScrapedAt = nil
            } else {
                continue
            }

            posting.companySlug = slug
            posting.companyDisplayName = company.displayName
            posting.platform = platformRaw
            posting.externalPath = path
            posting.externalId = job.externalId
            posting.title = job.title
            let displayLocation = WorkdayPostingParsing.displayLocation(
                listText: job.locationText,
                externalPath: path
            )
            posting.locationText = displayLocation
            posting.locationsFilterText = WorkdayPostingParsing.joinFilterLocations(
                WorkdayPostingParsing.resolvedFilterLocations(
                    listText: job.locationText,
                    externalPath: path,
                    detailPrimary: nil,
                    detailAdditional: nil
                )
            )
            posting.postedOnText = job.postedOn
            posting.postedAt = WorkdayPostingParsing.parsePostedOn(job.postedOn) ?? posting.postedAt
            if let jobType = job.jobTypeText, !jobType.isEmpty { posting.jobTypeText = jobType }
            if let timeType = job.timeType, !timeType.isEmpty { posting.timeType = timeType }
            posting.listingHash = newHash
            posting.applyURLString = WorkdayURLValidation.normalizedApplyURLString(job.applyURLString)
        }

        try deactivateMissingPostings(companySlug: slug, keeping: seenPaths)
        ModelMergeCoalescer.scheduleSave(context)
        return seenPaths.count
    }

    private func fetchOrCreatePosting(companySlug: String, externalPath: String) throws -> WorkdayJobPosting {
        if let existing = try fetchPosting(companySlug: companySlug, externalPath: externalPath) {
            return existing
        }
        let posting = WorkdayJobPosting(
            id: UUID(),
            companySlug: companySlug,
            externalId: externalPath,
            isActive: true
        )
        posting.externalPath = externalPath
        context.insert(posting)
        return posting
    }

    private func deactivateMissingPostings(companySlug: String, keeping seenPaths: Set<String>) throws {
        let active = try fetchCompanyPostings(companySlug: companySlug)
        for posting in active where posting.isActive {
            let path = posting.externalPath ?? ""
            if !seenPaths.contains(path) {
                posting.isActive = false
            }
        }
    }
}