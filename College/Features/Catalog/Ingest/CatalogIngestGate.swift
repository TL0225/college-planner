// CatalogIngestGate.swift
// Feature: Catalog
// Purpose: Orchestrates sanity + invariants + recovery before catalog persist.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogIngestGate {
    struct Outcome: Sendable {
        let metrics: CatalogExtractorMetrics
        let invariantResult: CatalogIngestRecoveryPolicy.InvariantResult
        let sanityResult: CatalogSanityConstraints.Result
        let recovery: CatalogIngestRecoveryPolicy.CatalogIngestRecoveryDecision
        let reviewSeverity: CatalogReviewSeverity
        let shouldAbortIngest: Bool
        let allowsRequirements: Bool
    }

    static func evaluateCourseLeaf(
        manifest: SchoolManifest,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        programs: [ScrapedProgram],
        courses: [CatalogCourse],
        requirements: [DegreeRequirement],
        layoutProfileID: String? = "legacy-courseleaf",
        averageEntityConfidence: Double? = nil,
        averageOwnershipConfidence: Double? = nil,
        startedAt: Date = Date()
    ) -> Outcome {
        let schoolID = manifest.id
        let version = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
        let expectCourses = depth == .full
        let expectPrograms = true
        let expectRequirements = depth == .full

        let metrics = CatalogExtractorMetrics(
            schoolID: schoolID,
            catalogVersionID: version.id,
            source: "courseleaf",
            layoutProfileID: layoutProfileID,
            programsFound: programs.count,
            coursesFound: courses.count,
            requirementsFound: requirements.count,
            policiesFound: 0,
            requirementTablesFound: requirements.count,
            averageEntityConfidence: averageEntityConfidence,
            averageOwnershipConfidence: averageOwnershipConfidence ?? averageEntityConfidence,
            recordedAt: Date()
        )

        let orphanCount = CatalogStructuralInvariantValidator.orphanRequirementCount(
            programs: programs,
            requirements: requirements
        )
        let invariantResult = CatalogStructuralInvariantValidator.validate(
            .init(
                expectPrograms: expectPrograms,
                expectCourses: expectCourses,
                expectRequirements: expectRequirements,
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                orphanRequirementCount: orphanCount
            )
        )

        let sanityResult = CatalogSanityConstraints.evaluate(
            metrics: metrics,
            expectCourses: expectCourses,
            expectPrograms: expectPrograms
        )

        let reviewSeverity: CatalogReviewSeverity = {
            if sanityResult.severity == .critical || !invariantResult.passed { return .critical }
            if !sanityResult.passed { return .warning }
            return .informational
        }()

        let recovery = CatalogIngestRecoveryPolicy.evaluate(
            metrics: .init(
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                policiesFound: metrics.policiesFound,
                expectCourses: expectCourses,
                expectRequirements: expectRequirements
            ),
            invariantResult: invariantResult,
            severity: reviewSeverity
        )

        enqueueReviewItems(
            schoolID: schoolID,
            metrics: metrics,
            reviewSeverity: reviewSeverity,
            sanityResult: sanityResult,
            invariantResult: invariantResult
        )

        let allowsRequirements = recovery.allowedScopes.contains(.requirements)
            && !recovery.blockedScopes.contains(.requirements)

        return Outcome(
            metrics: metrics,
            invariantResult: invariantResult,
            sanityResult: sanityResult,
            recovery: recovery,
            reviewSeverity: reviewSeverity,
            shouldAbortIngest: reviewSeverity.blocksIngest,
            allowsRequirements: allowsRequirements
        )
    }

    static func evaluatePDF(
        manifest: SchoolManifest,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        programs: [ScrapedProgram],
        courses: [CatalogCourse],
        requirements: [DegreeRequirement],
        policies: Int,
        layoutProfileID: String? = nil,
        averageProgramConfidence: Double? = nil
    ) -> Outcome {
        let schoolID = manifest.id
        let version = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
        let expectCourses = depth == .full
        let expectPrograms = true
        let expectRequirements = depth == .full
        let expectPolicies = depth == .light

        let metrics = CatalogExtractorMetrics(
            schoolID: schoolID,
            catalogVersionID: version.id,
            source: "pdf",
            layoutProfileID: layoutProfileID,
            programsFound: programs.count,
            coursesFound: courses.count,
            requirementsFound: requirements.count,
            policiesFound: policies,
            requirementTablesFound: requirements.count,
            averageEntityConfidence: averageProgramConfidence,
            averageOwnershipConfidence: averageProgramConfidence,
            recordedAt: Date()
        )

        let orphanCount = CatalogStructuralInvariantValidator.orphanRequirementCount(
            programs: programs,
            requirements: requirements
        )
        let invariantResult = CatalogStructuralInvariantValidator.validate(
            .init(
                expectPrograms: expectPrograms,
                expectCourses: expectCourses,
                expectRequirements: expectRequirements,
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                orphanRequirementCount: orphanCount
            )
        )

        let sanityResult = CatalogSanityConstraints.evaluate(
            metrics: metrics,
            expectCourses: expectCourses,
            expectPrograms: expectPrograms
        )

        let reviewSeverity: CatalogReviewSeverity = {
            if sanityResult.severity == .critical || !invariantResult.passed { return .critical }
            if !sanityResult.passed { return .warning }
            return .informational
        }()

        let recovery = CatalogIngestRecoveryPolicy.evaluate(
            metrics: .init(
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                policiesFound: metrics.policiesFound,
                expectCourses: expectCourses,
                expectRequirements: expectRequirements,
                expectPolicies: expectPolicies
            ),
            invariantResult: invariantResult,
            severity: reviewSeverity
        )

        enqueueReviewItems(
            schoolID: schoolID,
            metrics: metrics,
            reviewSeverity: reviewSeverity,
            sanityResult: sanityResult,
            invariantResult: invariantResult
        )

        let allowsRequirements = recovery.allowedScopes.contains(.requirements)
            && !recovery.blockedScopes.contains(.requirements)

        return Outcome(
            metrics: metrics,
            invariantResult: invariantResult,
            sanityResult: sanityResult,
            recovery: recovery,
            reviewSeverity: reviewSeverity,
            shouldAbortIngest: reviewSeverity.blocksIngest,
            allowsRequirements: allowsRequirements
        )
    }

    static func evaluateModernCampus(
        manifest: SchoolManifest,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        programs: [ScrapedProgram],
        courses: [CatalogCourse],
        requirements: [DegreeRequirement],
        layoutProfileID: String? = nil,
        expectCourses: Bool? = nil,
        startedAt: Date = Date()
    ) -> Outcome {
        let schoolID = manifest.id
        let version = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
        let expectCoursesResolved = expectCourses ?? (depth == .full)
        let expectPrograms = true
        let expectRequirements = depth == .full

        let metrics = CatalogExtractorMetrics(
            schoolID: schoolID,
            catalogVersionID: version.id,
            source: "moderncampus",
            layoutProfileID: layoutProfileID,
            programsFound: programs.count,
            coursesFound: courses.count,
            requirementsFound: requirements.count,
            policiesFound: 0,
            requirementTablesFound: requirements.count,
            averageEntityConfidence: nil,
            averageOwnershipConfidence: nil,
            recordedAt: Date()
        )

        let orphanCount = CatalogStructuralInvariantValidator.orphanRequirementCount(
            programs: programs,
            requirements: requirements
        )
        let invariantResult = CatalogStructuralInvariantValidator.validate(
            .init(
                expectPrograms: expectPrograms,
                expectCourses: expectCoursesResolved,
                expectRequirements: expectRequirements,
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                orphanRequirementCount: orphanCount
            )
        )

        let sanityResult = CatalogSanityConstraints.evaluate(
            metrics: metrics,
            expectCourses: expectCoursesResolved,
            expectPrograms: expectPrograms
        )

        let reviewSeverity: CatalogReviewSeverity = {
            if sanityResult.severity == .critical || !invariantResult.passed { return .critical }
            if !sanityResult.passed { return .warning }
            return .informational
        }()

        let recovery = CatalogIngestRecoveryPolicy.evaluate(
            metrics: .init(
                programsFound: metrics.programsFound,
                coursesFound: metrics.coursesFound,
                requirementsFound: metrics.requirementsFound,
                policiesFound: metrics.policiesFound,
                expectCourses: expectCoursesResolved,
                expectRequirements: expectRequirements
            ),
            invariantResult: invariantResult,
            severity: reviewSeverity
        )

        enqueueReviewItems(
            schoolID: schoolID,
            metrics: metrics,
            reviewSeverity: reviewSeverity,
            sanityResult: sanityResult,
            invariantResult: invariantResult
        )

        let allowsRequirements = recovery.allowedScopes.contains(.requirements)
            && !recovery.blockedScopes.contains(.requirements)

        return Outcome(
            metrics: metrics,
            invariantResult: invariantResult,
            sanityResult: sanityResult,
            recovery: recovery,
            reviewSeverity: reviewSeverity,
            shouldAbortIngest: reviewSeverity.blocksIngest,
            allowsRequirements: allowsRequirements
        )
    }

    static func recordSuccessfulBaseline(_ outcome: Outcome) {
        guard outcome.recovery.outcome != .fail else { return }
        CatalogExtractorMetricsBaselineStore.save(outcome.metrics)
        recordLayoutFingerprintAndDetectDrift(outcome.metrics)
    }

    private static func enqueueReviewItems(
        schoolID: String,
        metrics: CatalogExtractorMetrics,
        reviewSeverity: CatalogReviewSeverity,
        sanityResult: CatalogSanityConstraints.Result,
        invariantResult: CatalogIngestRecoveryPolicy.InvariantResult
    ) {
        if !sanityResult.passed, reviewSeverity != .critical {
            for message in sanityResult.messages {
                CatalogReviewQueue.enqueue(
                    schoolID: schoolID,
                    reason: message,
                    severity: sanityResult.severity,
                    metrics: metrics,
                    contextMessages: sanityResult.messages
                )
            }
        }

        if reviewSeverity == .critical {
            let reasons = invariantResult.criticalMessages + sanityResult.messages
            for reason in reasons {
                CatalogReviewQueue.enqueue(
                    schoolID: schoolID,
                    reason: reason,
                    severity: .critical,
                    metrics: metrics,
                    contextMessages: reasons
                )
            }
        }
    }

    private static func recordLayoutFingerprintAndDetectDrift(_ metrics: CatalogExtractorMetrics) {
        let current = CatalogLayoutFingerprint.from(metrics: metrics)
        let previous = CatalogLayoutFingerprintStore.load(
            schoolID: metrics.schoolID,
            catalogVersionID: metrics.catalogVersionID
        )
        let drift = CatalogLayoutDriftDetector.evaluate(previous: previous, current: current)
        if drift.detected {
            CatalogReviewQueue.enqueue(
                schoolID: metrics.schoolID,
                reason: "catalog_layout_drift: \(drift.message)",
                severity: .warning,
                metrics: metrics,
                contextMessages: [drift.message]
            )
        }
        CatalogLayoutFingerprintStore.save(current)
        CatalogLayoutCorpus.record(metrics: metrics, fingerprint: current)
    }
}
