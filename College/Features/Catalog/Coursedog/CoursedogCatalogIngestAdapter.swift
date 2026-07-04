// CoursedogCatalogIngestAdapter.swift
// Feature: Catalog
// Purpose: Light-depth program index ingest for Coursedog catalogs.

import Foundation

@MainActor
enum CoursedogCatalogIngestAdapter {
    private static let minimumProgramsForCompleteIndex = 5

    static func runCoursedogCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        hooks: CatalogBackgroundSyncRunner.Hooks?
    ) async throws -> CatalogBackgroundSyncRunner.CatalogIngestSyncOutcome {
        let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else { throw ScraperError.invalidURL }

        _ = await CatalogPlatformProbe.probe(catalogURL: catalogURL, manifest: manifest)

        hooks?.onVisualPhase?(.discovering)
        hooks?.onProgress?(0.15, "Discovering Coursedog programs…")
        notifications.update(id: toastID, message: "Discovering Coursedog programs…", progress: 0.15)

        let output = try await CoursedogEngine.discoverPrograms(catalogURL: catalogURL)
        try CatalogIngestCheckpoint.throwIfCancelled(schoolID: manifest.id)

        let ingestSignature = output.sourceSignature
        let forceRescrape = CatalogBackgroundSyncRunner.consumeForceNextRescrapeIfNeeded()
        CatalogBackgroundSyncRunner.invalidateIngestBaselineIfDiscoveryChanged(
            manifest: manifest,
            depth: depth,
            ingestSignature: ingestSignature,
            forceRescrape: forceRescrape,
            format: "coursedog"
        )

        if !forceRescrape,
           CatalogBackgroundSyncRunner.storedIngestSignature(schoolID: manifest.id, format: "coursedog", depth: depth) == ingestSignature {
            let presence = await collegePersistence.catalogPresence(universityName: manifest.name)
            if presence.majors + presence.minors >= minimumProgramsForCompleteIndex {
                let message = "Coursedog catalog unchanged — skipped incremental sync."
                hooks?.onProgress?(1.0, message)
                notifications.update(id: toastID, message: message, progress: 1.0)
                return .skipped(message: message)
            }
        }

        if output.programs.isEmpty {
            throw ScraperError.ingestRejected("No Coursedog programs were discovered from the catalog URL.")
        }

        if CatalogPlatformFlags.ingestGateEnabled {
            let gate = CatalogIngestGate.evaluateCourseLeaf(
                manifest: manifest,
                depth: depth,
                programs: output.programs,
                courses: [],
                requirements: []
            )
            if gate.shouldAbortIngest {
                throw ScraperError.ingestRejected(CatalogIngestGate.abortSummary(gate))
            }
        }

        hooks?.onVisualPhase?(.importing)
        hooks?.onProgress?(0.55, "Saving \(output.programs.count) programs…")
        notifications.update(id: toastID, message: "Saving program list…", progress: 0.55)

        let emptyProfile = SchoolProfile(
            schoolID: manifest.id,
            schoolName: manifest.name,
            catalogURL: catalogURL,
            version: "1.0.0-coursedog-programs",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        try await collegePersistence.importSchoolCatalog(emptyProfile, policy: .preserveExistingCourses)

        let rows = CatalogBackgroundSyncRunner.buildMajorRows(
            from: output.programs,
            extractedRequirements: [],
            mappingSource: "coursedog|programs-index",
            degreeLevelForProgram: { _ in DegreeConfiguration.undergraduate }
        )
        try CatalogBackgroundSyncRunner.saveChunkedMajorsWithCatoid(
            rows.map { row in
                (
                    name: row.name,
                    degreeLevel: row.degreeLevel,
                    degreeType: row.degreeType,
                    isMinor: row.isMinor,
                    department: row.department,
                    url: row.url,
                    resolvedDepartment: row.resolvedDepartment,
                    resolvedCollege: row.resolvedCollege,
                    mappingConfidence: row.mappingConfidence,
                    mappingSource: row.mappingSource,
                    requirements: row.requirements,
                    sourceCatalogCatoid: "coursedog",
                    trackVariant: row.trackVariant,
                    parentProgramKey: row.parentProgramKey,
                    catalogStableID: nil,
                    provenanceJSON: nil
                )
            },
            for: manifest.name,
            schoolID: manifest.id,
            collegePersistence: collegePersistence
        )

        CatalogIngestCheckpoint.save(stage: .passA, schoolID: manifest.id, signature: ingestSignature)
        CatalogBackgroundSyncRunner.setStoredIngestSignature(
            ingestSignature,
            schoolID: manifest.id,
            format: "coursedog",
            depth: depth
        )

        if let university = collegePersistence.getActiveUniversity() {
            CatalogSyncProgressReporter.emitPhaseACommitted(
                universityID: university.id,
                programCount: output.programs.count,
                hooks: hooks
            )
        }

        _ = collegePersistence.setActiveUniversity(named: manifest.name)
        hooks?.onProgress?(1.0, "Catalog programs saved.")
        notifications.update(id: toastID, message: "Catalog programs saved.", progress: 1.0)
        return .completed(scheduledPassB: false)
    }
}
