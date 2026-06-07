// CatalogIngestRecoveryPolicy.swift
// Feature: Catalog
// Purpose: Catalog module — scoped pass/partial/fail ingest recovery decisions.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogIngestRecoveryPolicy {
    enum IngestScope: String, Codable, Sendable, CaseIterable {
        case programs
        case courses
        case requirements
        case policies
    }

    enum RecoveryOutcome: String, Codable, Sendable, CaseIterable {
        case pass
        case partial
        case fail
    }

    struct CatalogIngestRecoveryDecision: Codable, Sendable, Equatable {
        let outcome: RecoveryOutcome
        let allowedScopes: [IngestScope]
        let blockedScopes: [IngestScope]
        let reasons: [String]
    }

    struct Metrics: Codable, Sendable, Equatable {
        let programsFound: Int
        let coursesFound: Int
        let requirementsFound: Int
        let policiesFound: Int
        let expectedPrograms: Int?
        let expectedCourses: Int?
        let expectCourses: Bool
        let expectRequirements: Bool
        let expectPolicies: Bool

        init(
            programsFound: Int,
            coursesFound: Int,
            requirementsFound: Int = 0,
            policiesFound: Int = 0,
            expectedPrograms: Int? = nil,
            expectedCourses: Int? = nil,
            expectCourses: Bool = true,
            expectRequirements: Bool = true,
            expectPolicies: Bool = false
        ) {
            self.programsFound = programsFound
            self.coursesFound = coursesFound
            self.requirementsFound = requirementsFound
            self.policiesFound = policiesFound
            self.expectedPrograms = expectedPrograms
            self.expectedCourses = expectedCourses
            self.expectCourses = expectCourses
            self.expectRequirements = expectRequirements
            self.expectPolicies = expectPolicies
        }
    }

    struct InvariantResult: Codable, Sendable, Equatable {
        let passed: Bool
        let failedScopes: [IngestScope]
        let criticalMessages: [String]
        let warningMessages: [String]

        init(
            passed: Bool,
            failedScopes: [IngestScope] = [],
            criticalMessages: [String] = [],
            warningMessages: [String] = []
        ) {
            self.passed = passed
            self.failedScopes = failedScopes
            self.criticalMessages = criticalMessages
            self.warningMessages = warningMessages
        }
    }

    static func evaluate(
        metrics: Metrics,
        invariantResult: InvariantResult,
        severity: CatalogReviewSeverity
    ) -> CatalogIngestRecoveryDecision {
        if severity == .critical || !invariantResult.passed {
            let blocked = orderedScopes(invariantResult.failedScopes.isEmpty
                ? IngestScope.allCases
                : invariantResult.failedScopes)
            let reasons = invariantResult.criticalMessages + sanityCriticalReasons(metrics: metrics)
            if blocked.count == IngestScope.allCases.count {
                return CatalogIngestRecoveryDecision(
                    outcome: .fail,
                    allowedScopes: [],
                    blockedScopes: blocked,
                    reasons: reasons.isEmpty ? ["Critical ingest failure."] : reasons
                )
            }
            let allowed = IngestScope.allCases.filter { !blocked.contains($0) }
            return CatalogIngestRecoveryDecision(
                outcome: .partial,
                allowedScopes: allowed,
                blockedScopes: blocked,
                reasons: reasons.isEmpty ? ["Partial ingest: one or more scopes failed invariants."] : reasons
            )
        }

        let softFailed = softFailedScopes(metrics: metrics)
        if softFailed.isEmpty {
            return CatalogIngestRecoveryDecision(
                outcome: .pass,
                allowedScopes: IngestScope.allCases,
                blockedScopes: [],
                reasons: []
            )
        }

        let allowed = IngestScope.allCases.filter { !softFailed.contains($0) }
        return CatalogIngestRecoveryDecision(
            outcome: .partial,
            allowedScopes: allowed,
            blockedScopes: softFailed,
            reasons: ["Partial ingest: low-confidence or empty scope results."]
        )
    }

    private static func softFailedScopes(metrics: Metrics) -> [IngestScope] {
        var failed: [IngestScope] = []
        if metrics.programsFound == 0 { failed.append(.programs) }
        if metrics.expectCourses, metrics.coursesFound == 0 { failed.append(.courses) }
        if metrics.expectRequirements, metrics.requirementsFound == 0 { failed.append(.requirements) }
        if metrics.expectPolicies, metrics.policiesFound == 0 { failed.append(.policies) }
        if failed.count == IngestScope.allCases.count {
            return [.requirements]
        }
        if failed.contains(.programs), failed.contains(.courses) {
            return failed
        }
        if failed == IngestScope.allCases {
            return [.requirements]
        }
        return failed.filter { $0 == .requirements || $0 == .policies }
    }

    private static func sanityCriticalReasons(metrics: Metrics) -> [String] {
        var reasons: [String] = []
        if metrics.coursesFound == 0 {
            reasons.append("No courses extracted.")
        }
        if let expectedPrograms = metrics.expectedPrograms,
           expectedPrograms > 0,
           metrics.programsFound < max(1, expectedPrograms / 2) {
            reasons.append("Program count fell below sanity baseline.")
        }
        if let expectedCourses = metrics.expectedCourses,
           expectedCourses > 0,
           metrics.coursesFound < max(1, expectedCourses / 2) {
            reasons.append("Course count fell below sanity baseline.")
        }
        return reasons
    }

    private static func orderedScopes(_ scopes: [IngestScope]) -> [IngestScope] {
        IngestScope.allCases.filter { scopes.contains($0) }
    }
}
