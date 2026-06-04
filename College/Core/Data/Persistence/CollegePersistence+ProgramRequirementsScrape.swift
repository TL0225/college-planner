// CollegePersistence+ProgramRequirementsScrape.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+ProgramRequirementsScrape.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

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
    ) async -> Int {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else {
            DebugLogger.shared.scraper("📚 Requirements: no active university")
            return -1
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
                return 0
            }
        }

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
                return existing.count
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
            return inserted
        } catch {
            DebugLogger.shared.scraper("❌ Requirements scrape failed: \(error)", level: .error)
            DebugLogger.shared.logError(error)
            return -1
        }
    }

    /// Network fetch + HTML parse off the main actor (Phase 5 P0).
    private func scrapeProgramRequirementsOffMain(programURL: String) async throws -> [DegreeRequirement] {
        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        return try await Task.detached(priority: .userInitiated) {
            let scraper = UniversalCatalogScraper()
            return try await scraper.scrapeProgramRequirements(programURL: canonicalURL)
        }.value
    }

    func refreshProgramRequirementsForCatalogPick(
        programURL: String,
        major: String,
        degreeType: String,
        universityName: String,
        force: Bool = false
    ) async -> RequirementsRefreshResult {
        let before = Date()
        let savedRowCount = await refreshProgramRequirementsIfNeeded(
            programURL: programURL,
            major: major,
            degreeType: degreeType,
            force: force
        )
        let elapsed = Date().timeIntervalSince(before)

        if savedRowCount < 0 {
            return RequirementsRefreshResult(
                programURL: programURL,
                skippedDueToFreshCache: false,
                savedRowCount: 0,
                savedCourseCount: 0,
                errorMessage: "Could not scrape \(major) — no catalog university match for “\(universityName)”."
            )
        }

        let skipped = savedRowCount == 0 && !force && elapsed < 0.5
        let savedCourseCount: Int = {
            guard let university = getActiveUniversity(),
                  let repo = catalogRepository else { return 0 }
            return (try? repo.countDistinctCourseCodesInProgramRequirements(
                universityID: university.id,
                programURL: programURL,
                degreeType: degreeType
            )) ?? 0
        }()

        return RequirementsRefreshResult(
            programURL: programURL,
            skippedDueToFreshCache: skipped,
            savedRowCount: max(0, savedRowCount),
            savedCourseCount: savedCourseCount,
            errorMessage: nil
        )
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