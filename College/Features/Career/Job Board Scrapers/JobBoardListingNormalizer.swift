// JobBoardListingNormalizer.swift
// Feature: Career / Job Board Scrapers
// Purpose: Normalize scraped fields for Openings filters.

import Foundation

enum JobBoardListingNormalizer {
    static func inferTimeType(from locationText: String?, tags: [String] = []) -> String? {
        let hay = ([locationText ?? ""] + tags).joined(separator: " ").lowercased()
        if hay.contains("remote") { return "Remote" }
        if hay.contains("hybrid") { return "Hybrid" }
        if hay.contains("onsite") || hay.contains("on-site") { return "On-site" }
        return nil
    }

    static func inferJobType(from text: String?) -> String? {
        guard let text else { return nil }
        let lower = text.lowercased()
        if lower.contains("full-time") || lower.contains("full time") { return "Full-time" }
        if lower.contains("part-time") || lower.contains("part time") { return "Part-time" }
        if lower.contains("contract") { return "Contract" }
        if lower.contains("intern") { return "Internship" }
        return nil
    }

    static func parsePostedOn(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeListing(
        externalId: String,
        externalPath: String,
        title: String,
        locationText: String?,
        postedOn: String?,
        applyURLString: String?,
        jobTypeText: String?,
        timeType: String?,
        tags: [String] = []
    ) -> ScrapedJobListing {
        let resolvedTime = timeType ?? inferTimeType(from: locationText, tags: tags)
        let resolvedJobType = jobTypeText ?? inferJobType(from: title)
        return ScrapedJobListing(
            externalId: externalId,
            externalPath: externalPath,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            locationText: locationText?.trimmingCharacters(in: .whitespacesAndNewlines),
            postedOn: parsePostedOn(postedOn),
            applyURLString: applyURLString,
            jobTypeText: resolvedJobType,
            timeType: resolvedTime,
            listingHash: JobListingHash.compute(title: title, locationsText: locationText)
        )
    }
}
