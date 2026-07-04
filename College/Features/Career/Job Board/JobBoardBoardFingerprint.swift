// JobBoardBoardFingerprint.swift
// Feature: Career / Job Board
// Purpose: Lightweight board snapshot for incremental list-sync probes.

import CryptoKit
import Foundation

/// First-page + total-count snapshot used to skip full pagination when nothing changed.
struct JobBoardBoardFingerprint: Codable, Equatable, Sendable {
    let boardTotal: Int
    let pageDigest: String

    static func digest(listings: [ScrapedJobListing]) -> String {
        let lines = listings
            .map { listing in
                let hash = listing.listingHash ?? JobListingHash.compute(
                    title: listing.title,
                    locationsText: listing.locationText
                )
                return "\(listing.externalPath)|\(hash)"
            }
            .sorted()
        let payload = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum JobBoardBoardFingerprintStore {
    private static func fingerprintKey(slug: String) -> String {
        "workday.boardFingerprint.\(slug)"
    }

    private static func lastFullListScrapeKey(slug: String) -> String {
        "workday.lastFullListScrapeAt.\(slug)"
    }

    static func storedFingerprint(slug: String) -> JobBoardBoardFingerprint? {
        guard let data = UserDefaults.standard.data(forKey: fingerprintKey(slug: slug)) else { return nil }
        return try? JSONDecoder().decode(JobBoardBoardFingerprint.self, from: data)
    }

    static func recordFingerprint(_ fingerprint: JobBoardBoardFingerprint, slug: String) {
        guard let data = try? JSONEncoder().encode(fingerprint) else { return }
        UserDefaults.standard.set(data, forKey: fingerprintKey(slug: slug))
    }

    static func lastFullListScrape(slug: String) -> Date? {
        UserDefaults.standard.object(forKey: lastFullListScrapeKey(slug: slug)) as? Date
    }

    static func recordFullListScrape(slug: String, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastFullListScrapeKey(slug: slug))
    }

    /// Whether a periodic full pagination pass is due (detects removals deep in the board).
    static func isDueForFullListScrape(slug: String, now: Date = Date()) -> Bool {
        guard let last = lastFullListScrape(slug: slug) else { return true }
        return now.timeIntervalSince(last) >= JobBoardThresholds.fullListRescrapeInterval
    }
}
