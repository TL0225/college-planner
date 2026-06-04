// CatalogSchoolDataPurgeRunner.swift
// Feature: Catalog
// Purpose: Catalog module — Target.
// Data: CollegePersistence / repositories when applicable.

import Combine
import Foundation

/// Runs catalog scrape purge with verification and menu-bar progress updates.
@MainActor
final class CatalogSchoolDataPurgeRunner: ObservableObject {
    static let shared = CatalogSchoolDataPurgeRunner()

    struct Target: Sendable, Equatable {
        let schoolID: String
        let universityName: String
        let catalogURL: String?
        let programURLNeedle: String?
    }

    struct ResultSummary: Sendable, Equatable {
        let clearedSchools: Int
        let deletedRows: Int
        let clearedSelectedProgramIDs: Int
        let remainingRows: Int
        let failures: [String]
    }

    @Published private(set) var isRunning = false
    @Published private(set) var statusLine: String = ""
    @Published private(set) var progressFraction: Double?
    @Published private(set) var lastSummary: ResultSummary?

    private init() {}

    func run(targets: [Target], persistence: CollegePersistence) async -> ResultSummary {
        guard !isRunning else {
            return lastSummary ?? ResultSummary(
                clearedSchools: 0,
                deletedRows: 0,
                clearedSelectedProgramIDs: 0,
                remainingRows: 0,
                failures: ["Purge already running"]
            )
        }

        isRunning = true
        statusLine = String(
            localized: "settings.general.catalog_clear_scraped_running",
            defaultValue: "Clearing…"
        )
        progressFraction = nil
        lastSummary = nil

        defer {
            isRunning = false
        }

        var deletedRows = 0
        var clearedSelected = 0
        var failures: [String] = []
        var clearedSchools = 0

        let totalSchools = max(1, targets.count)
        for (index, target) in targets.enumerated() {
            let schoolLabel = target.universityName
            statusLine = String(
                format: String(
                    localized: "settings.general.catalog_clear_scraped_school_fmt",
                    defaultValue: "Clearing %@…"
                ),
                schoolLabel
            )
            let baseFraction = Double(index) / Double(totalSchools)
            CatalogSchoolScrapePurgeNotifier.postInProgress(
                fraction: baseFraction,
                title: statusLine,
                indeterminate: true,
                completedCount: index,
                totalCount: totalSchools,
                stage: String(localized: "settings.general.catalog_clear_scraped_stage", defaultValue: "Clear")
            )

            do {
                let report = try await CatalogSchoolDataPurge.purge(
                    schoolID: target.schoolID,
                    universityName: target.universityName,
                    catalogURL: target.catalogURL,
                    collegePersistence: persistence
                )
                deletedRows += report.storePurgeCounts.total
                clearedSelected += report.clearedSelectedProgramIDs
                clearedSchools += 1
            } catch {
                failures.append("\(schoolLabel): \(error.localizedDescription)")
            }
        }

        let verification = await verifyCleared(
            targets: targets,
            persistence: persistence,
            maxAttempts: 5
        )
        deletedRows += verification.extraDeletedRows
        failures.append(contentsOf: verification.failures)

        let remaining = persistence.catalogScrapeDataPresence(
            forUniversityNames: targets.map(\.universityName),
            programURLNeedles: targets.map(\.programURLNeedle)
        )

        let summary = ResultSummary(
            clearedSchools: clearedSchools,
            deletedRows: deletedRows,
            clearedSelectedProgramIDs: clearedSelected,
            remainingRows: remaining.total,
            failures: failures
        )
        lastSummary = summary

        if remaining.isEmpty, failures.isEmpty {
            statusLine = String(
                localized: "settings.general.catalog_clear_scraped_verified",
                defaultValue: "Catalog scrape data cleared"
            )
            progressFraction = 1
            CatalogSchoolScrapePurgeNotifier.postFinished(
                summary: statusLine
            )
        } else if remaining.isEmpty {
            statusLine = String(
                localized: "settings.general.catalog_clear_scraped_partial",
                defaultValue: "Data cleared with warnings"
            )
            CatalogSchoolScrapePurgeNotifier.postFinished(
                summary: statusLine,
                failed: true,
                message: failures.joined(separator: " · ")
            )
        } else {
            statusLine = String(
                format: String(
                    localized: "settings.general.catalog_clear_scraped_remaining_fmt",
                    defaultValue: "%d catalog rows still remain — try again"
                ),
                remaining.total
            )
            CatalogSchoolScrapePurgeNotifier.postFinished(
                summary: statusLine,
                failed: true,
                message: failures.joined(separator: " · ")
            )
        }

        CatalogBackgroundSyncRunner.setForceNextRescrape(true)
        persistence.bumpCatalogDataRevision()
        return summary
    }

    private struct VerificationOutcome {
        var extraDeletedRows: Int = 0
        var failures: [String] = []
    }

    private func verifyCleared(
        targets: [Target],
        persistence: CollegePersistence,
        maxAttempts: Int
    ) async -> VerificationOutcome {
        var outcome = VerificationOutcome()

        for attempt in 1...maxAttempts {
            let presence = persistence.catalogScrapeDataPresence(
                forUniversityNames: targets.map(\.universityName),
                programURLNeedles: targets.map(\.programURLNeedle)
            )
            guard !presence.isEmpty else {
                progressFraction = 1
                return outcome
            }

            statusLine = String(
                format: String(
                    localized: "settings.general.catalog_clear_scraped_verify_fmt",
                    defaultValue: "Verifying… %d rows remain (pass %d)"
                ),
                presence.total,
                attempt
            )
            progressFraction = Double(maxAttempts - attempt) / Double(maxAttempts)
            CatalogSchoolScrapePurgeNotifier.postInProgress(
                fraction: progressFraction ?? 0,
                title: statusLine,
                indeterminate: false,
                completedCount: maxAttempts - attempt,
                totalCount: maxAttempts,
                stage: String(localized: "settings.general.catalog_clear_scraped_verify_stage", defaultValue: "Verify")
            )

            for target in targets {
                let counts = persistence.purgeCatalogScrapeData(
                    forUniversityName: target.universityName,
                    programURLContains: target.programURLNeedle
                )
                outcome.extraDeletedRows += counts.total
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let remaining = persistence.catalogScrapeDataPresence(
            forUniversityNames: targets.map(\.universityName),
            programURLNeedles: targets.map(\.programURLNeedle)
        )
        if !remaining.isEmpty {
            outcome.failures.append(
                String(
                    format: String(
                        localized: "settings.general.catalog_clear_scraped_verify_failed_fmt",
                        defaultValue: "%d catalog rows still present after verification"
                    ),
                    remaining.total
                )
            )
        }
        return outcome
    }
}
