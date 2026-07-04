// CollegePersistence+ProgramRequirementsScrape.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+ProgramRequirementsScrape.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Outcome of a single program-requirements scrape attempt. Distinguishes a genuine
/// fresh-cache skip from a scrape that ran but produced nothing — the latter must NOT
/// be reported to the user as "already fresh".
enum ProgramRequirementsScrapeOutcome: Sendable {
    /// Could not run: no active university, or the fetch/parse threw.
    case failed
    /// Existing requirements were within the freshness window; nothing was fetched.
    case skippedFresh
    /// Re-fetched, but the parsed requirements were byte-identical to what is stored.
    case unchanged(existingRowCount: Int)
    /// Requirements were (re)written. `rowCount == 0` means the page was reachable but
    /// yielded no parseable requirement categories (a real parser miss, not a cache hit).
    case saved(rowCount: Int)
}

@MainActor
extension CollegePersistence {
    /// Scrape and persist program requirements into local store catalog storage.
    func refreshProgramRequirementsIfNeeded(
        programURL: String,
        major: String,
        degreeType: String,
        force: Bool = false,
        minimumRefreshIntervalSeconds: TimeInterval = {
            #if DEBUG
            return 30
            #else
            return 24 * 60 * 60
            #endif
        }()
    ) async -> ProgramRequirementsScrapeOutcome {
        await BackgroundServiceOnDemand.runReturning(id: "program_requirements_scrape") {
            await self.refreshProgramRequirementsIfNeededImpl(
                programURL: programURL,
                major: major,
                degreeType: degreeType,
                force: force,
                minimumRefreshIntervalSeconds: minimumRefreshIntervalSeconds
            )
        }
    }

    private func refreshProgramRequirementsIfNeededImpl(
        programURL: String,
        major: String,
        degreeType: String,
        force: Bool = false,
        minimumRefreshIntervalSeconds: TimeInterval
    ) async -> ProgramRequirementsScrapeOutcome {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else {
            DebugLogger.shared.scraper("📚 Requirements: no active university")
            return .failed
        }

        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        let existing = getDegreeRequirements(programURL: canonicalURL, degreeType: degreeType)
        let existingHash = existing.first?.requirementsHash
        let existingLastScraped = existing.first?.lastScrapedAt

        if !force, let last = existingLastScraped {
            let age = Date().timeIntervalSince(last)
            if age < minimumRefreshIntervalSeconds {
                DebugLogger.shared.scraper(
                    "📚 Requirements: skip scrape (fresh) major=\(major) degreeType=\(degreeType) age=\(Int(age))s"
                )
                return .skippedFresh
            }
        }

        let activityID = BackgroundActivityCenter.programRequirementsActivityID(programURL: canonicalURL)
        BackgroundActivityReporter.running(
            id: activityID,
            domain: .catalog,
            title: major,
            detail: String(localized: "catalog.background.program_requirements", defaultValue: "Scraping degree requirements…"),
            indeterminate: true
        )

        do {
            var parsed = try await scrapeProgramRequirementsOffMain(programURL: programURL)
            parsed = enrichDegreeRequirementsFromCatalog(parsed)
            updateCatalogTitlesFromRequirements(parsed)

            let newHash = AcademicProgramHelpers.stableRequirementsHash(parsed)
            if !force, let existingHash, existingHash == newHash {
                try repo.touchProgramRequirementsFreshness(
                    universityID: university.id,
                    programURL: canonicalURL,
                    degreeType: degreeType
                )
                _ = try? appDataStore.catalogSave()
                bumpCatalogDataRevision()
                BackgroundActivityReporter.finish(
                    id: activityID,
                    succeeded: true,
                    summary: String(localized: "catalog.background.program_requirements_unchanged", defaultValue: "Requirements up to date")
                )
                return .unchanged(existingRowCount: existing.count)
            }

            let inserted = try repo.replaceProgramRequirements(
                universityID: university.id,
                programURL: canonicalURL,
                degreeType: degreeType,
                major: major,
                categories: parsed,
                requirementsHash: newHash
            )
            _ = try? appDataStore.catalogSave()
            bumpCatalogDataRevision()

            if inserted > 0 {
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Degree Requirements Updated",
                    message: "\(major) requirements have changed since your last sync. Review the Detailed Audit."
                )
            }
            BackgroundActivityReporter.finish(
                id: activityID,
                succeeded: true,
                summary: inserted > 0
                    ? String(format: String(localized: "catalog.background.program_requirements_saved", defaultValue: "%d requirement categories saved"), inserted)
                    : String(localized: "catalog.background.program_requirements_empty", defaultValue: "Scrape finished with no parseable requirements")
            )
            if inserted > 0 {
                AcademicCalendarImportPromptBridge.schedulePromptIfAppropriate(persistence: self)
            }
            return .saved(rowCount: inserted)
        } catch {
            DebugLogger.shared.scraper("❌ Requirements scrape failed: \(error)", level: .error)
            DebugLogger.shared.logError(error)
            BackgroundActivityReporter.finish(
                id: activityID,
                succeeded: false,
                summary: error.localizedDescription
            )
            return .failed
        }
    }

    /// Network fetch + HTML parse off the main actor (Phase 5 P0).
    private func scrapeProgramRequirementsOffMain(programURL: String) async throws -> [DegreeRequirement] {
        let catalogFormat: String? = CoursedogEngine.isCoursedogProgramURL(programURL) ? "coursedog" : nil
        return try await Task.detached(priority: .userInitiated) {
            let scraper = UniversalCatalogScraper()
            return try await scraper.scrapeProgramRequirements(
                programURL: programURL,
                catalogFormat: catalogFormat,
                politeness: .bulk
            )
        }.value
    }

    func refreshProgramRequirementsForCatalogPick(
        programURL: String,
        major: String,
        degreeType: String,
        universityName: String,
        force: Bool = false
    ) async -> RequirementsRefreshResult {
        let outcome = await refreshProgramRequirementsIfNeeded(
            programURL: programURL,
            major: major,
            degreeType: degreeType,
            force: force
        )

        func currentCourseCount() -> Int {
            guard let university = getActiveUniversity(),
                  let repo = catalogRepository else { return 0 }
            return (try? repo.countDistinctCourseCodesInProgramRequirements(
                universityID: university.id,
                programURL: programURL,
                degreeType: degreeType
            )) ?? 0
        }

        switch outcome {
        case .failed:
            return RequirementsRefreshResult(
                programURL: programURL,
                skippedDueToFreshCache: false,
                savedRowCount: 0,
                savedCourseCount: 0,
                errorMessage: "Could not scrape \(major) — the catalog page couldn’t be fetched, or there’s no catalog match for “\(universityName)”."
            )
        case .skippedFresh:
            return RequirementsRefreshResult(
                programURL: programURL,
                skippedDueToFreshCache: true,
                savedRowCount: 0,
                savedCourseCount: currentCourseCount(),
                errorMessage: nil
            )
        case .unchanged(let existingRowCount):
            return RequirementsRefreshResult(
                programURL: programURL,
                skippedDueToFreshCache: false,
                savedRowCount: existingRowCount,
                savedCourseCount: currentCourseCount(),
                errorMessage: nil
            )
        case .saved(let rowCount):
            // rowCount == 0 here means the page was reachable but produced no categories.
            // It is intentionally NOT reported as "fresh"; the caller surfaces the miss.
            return RequirementsRefreshResult(
                programURL: programURL,
                skippedDueToFreshCache: false,
                savedRowCount: rowCount,
                savedCourseCount: currentCourseCount(),
                errorMessage: nil
            )
        }
    }

    private func enrichDegreeRequirementsFromCatalog(_ requirements: [DegreeRequirement]) -> [DegreeRequirement] {
        func bestDetail(_ detail: CourseDetail) -> CourseDetail {
            let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(detail.code)
            guard !code.isEmpty, let catalog = getCatalogCourse(code: code) else { return detail }

            let title = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let catalogTitle = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let bestTitle: String? = {
                if title.isEmpty { return catalogTitle.isEmpty ? nil : catalogTitle }
                if AcademicProgramHelpers.normalizeCourseCodeForProgress(title) == code {
                    return catalogTitle.isEmpty ? nil : catalogTitle
                }
                return title
            }()

            let bestCredits: String? = {
                if let credits = detail.credits, !credits.isEmpty { return credits }
                let resolved = Int(catalog.credits)
                return resolved > 0 ? String(resolved) : nil
            }()

            return CourseDetail(code: code, title: bestTitle, credits: bestCredits)
        }

        return requirements.map { requirement in
            DegreeRequirement(
                id: requirement.id,
                degreeType: requirement.degreeType,
                major: requirement.major,
                category: requirement.category,
                requiredCourses: requirement.requiredCourses,
                requiredCoursesDetailed: requirement.requiredCoursesDetailed?.map(bestDetail),
                creditsRequired: requirement.creditsRequired,
                description: requirement.description,
                selectFrom: requirement.selectFrom,
                selectFromDetailed: requirement.selectFromDetailed?.map(bestDetail),
                selectCount: requirement.selectCount,
                requirementKind: requirement.requirementKind,
                parentCategory: requirement.parentCategory,
                displayTitle: requirement.displayTitle
            )
        }
    }

    private func updateCatalogTitlesFromRequirements(_ requirements: [DegreeRequirement]) {
        let details = requirements.flatMap { ($0.requiredCoursesDetailed ?? []) + ($0.selectFromDetailed ?? []) }
        guard !details.isEmpty else { return }

        for detail in details {
            let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(detail.code)
            guard !code.isEmpty,
                  let title = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let catalog = getCatalogCourse(code: code) else { continue }

            let current = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty
                || AcademicProgramHelpers.normalizeCourseCodeForProgress(current) == code {
                catalog.title = title
                catalog.lastUpdated = .now
            }
        }
        _ = try? appDataStore.catalogSave()
    }
}