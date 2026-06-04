// AuditSnapshotStore.swift
// Feature: Academics
// Purpose: Academics module — AcademicsCreditBuckets.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation
import SwiftData
import SwiftUI

/// Credit distribution buckets for the Academics summary strip and graduation sheet.
struct AcademicsCreditBuckets: Equatable, Sendable {
    var completed: Int = 0
    var inProgress: Int = 0
    var planned: Int = 0
    var remaining: Int = 0
}

/// Cached Academics credit layout (programs breakdown, buckets, bottom strip rows).
struct AcademicsCreditLayoutSnapshot: Equatable {
    var programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown
    var resolvedGraduationCreditsRequired: Int
    var combinedRequired: Int
    var buckets: AcademicsCreditBuckets
    var programCreditRows: [ProgramCreditStatusStripRow]
}

struct AcademicsCourseCreditLine: Sendable, Equatable {
    let credits: Int
    let isCompleted: Bool
    let status: String?
}

/// Holds audit and credit-layout snapshots for the Academics tab; heavy work is scheduled off the view `body`.
@Observable
@MainActor
final class AuditSnapshotStore {
    private(set) var auditDegrees: [AcademicsAuditPanel.AuditDegree] = []
    private(set) var isLoadingAudit = false
    private(set) var creditLayout: AcademicsCreditLayoutSnapshot?

    private var creditRefreshTask: Task<Void, Never>?
    private var lastCreditInvalidationToken: String = ""

    private var auditLoadTask: Task<Void, Never>?

    // MARK: - Audit reload

    func reloadAudit(
        collegePersistence: CollegePersistence,
        majors: [String],
        minors: [String],
        academicProfile: AcademicProfile?
    ) async -> Set<UUID> {
        isLoadingAudit = true
        await Task.yield()

        let previous = auditDegrees
        let built = await buildAuditDegrees(
            collegePersistence: collegePersistence,
            majors: majors,
            minors: minors,
            academicProfile: academicProfile,
            previousAuditDegrees: previous
        )

        guard !Task.isCancelled else {
            isLoadingAudit = false
            return []
        }

        auditDegrees = built.0
        isLoadingAudit = false
        return built.1
    }

    func scheduleReloadAudit(
        collegePersistence: CollegePersistence,
        majors: [String],
        minors: [String],
        academicProfile: AcademicProfile?,
        onExpanded: @escaping @MainActor (Set<UUID>) -> Void
    ) {
        auditLoadTask?.cancel()
        auditLoadTask = Task {
            let hints = await reloadAudit(
                collegePersistence: collegePersistence,
                majors: majors,
                minors: minors,
                academicProfile: academicProfile
            )
            guard !Task.isCancelled else { return }
            onExpanded(hints)
        }
    }

    // MARK: - Credit layout

    static func creditLayoutToken(
        academicProfileID: UUID?,
        majors: [String],
        minors: [String],
        semesterCourseCount: Int,
        specializationSelectionVersion: Int,
        metricsCreditsRequired: Int?
    ) -> String {
        [
            academicProfileID?.uuidString ?? "",
            majors.joined(separator: "\u{1e}"),
            minors.joined(separator: "\u{1e}"),
            "\(semesterCourseCount)",
            "\(specializationSelectionVersion)",
            "\(metricsCreditsRequired ?? -1)",
        ].joined(separator: "|")
    }

    static func courseCreditLines(from plannerSemesters: [PlannerSemester]) -> [AcademicsCourseCreditLine] {
        plannerSemesters.flatMap { semester in
            (semester.courses ?? []).map { course in
                AcademicsCourseCreditLine(
                    credits: Int(course.credits),
                    isCompleted: course.isCompleted,
                    status: course.status
                )
            }
        }
    }

    func scheduleCreditLayoutRefresh(
        token: String,
        collegePersistence: CollegePersistence,
        academicProfile: AcademicProfile?,
        majors: [String],
        minors: [String],
        plannerSemesters: [PlannerSemester],
        metricsCreditsRequired: Int?
    ) {
        if token == lastCreditInvalidationToken, creditLayout != nil { return }
        creditRefreshTask?.cancel()
        creditRefreshTask = Task(priority: .userInitiated) {
            let breakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown = await Task(priority: .userInitiated) { @MainActor in
                if let academicProfile {
                    return collegePersistence.declaredProgramsCreditsBreakdown(for: academicProfile)
                }
                return collegePersistence.declaredProgramsCreditsBreakdown()
            }.value

            guard !Task.isCancelled else { return }

            let primaryRequired = breakdown.primary.requiredRoundedInt
            let resolvedGraduationCreditsRequired: Int = await Task(priority: .userInitiated) { @MainActor in
                if primaryRequired > 0 { return primaryRequired }
                if let fromSnapshot = metricsCreditsRequired, fromSnapshot > 0 { return fromSnapshot }
                let live = Int(collegePersistence.primaryDeclaredProgramRequirementCredits().rounded())
                if live > 0 { return live }
                let pr = collegePersistence.primaryCreditsRequired()
                if pr == 120,
                   let inferred = DeclaredProgramDegreeMetadata.infer(
                    fromProgramDisplays: collegePersistence.resolvedMajorNames()
                   ),
                   !DegreeConfiguration.isUndergraduate(inferred.degreeLevel) {
                    return 0
                }
                return pr > 0 ? pr : 0
            }.value

            let combinedRequired: Int = {
                let allPrograms = breakdown.allProgramsRequiredTotal
                if allPrograms > 0 { return allPrograms }
                return resolvedGraduationCreditsRequired
            }()

            let courseLines: [AcademicsCourseCreditLine] = {
                if !plannerSemesters.isEmpty {
                    return Self.courseCreditLines(from: plannerSemesters)
                }
                return Self.courseCreditLines(from: plannerSemesters)
            }()

            let buckets = await Task.detached(priority: .userInitiated) {
                Self.computeBuckets(courseLines: courseLines, required: combinedRequired)
            }.value

            guard !Task.isCancelled else { return }

            let programCreditRows = await Task(priority: .userInitiated) { @MainActor in
                collegePersistence.programCreditStatusStripRows(
                    majors: majors,
                    minors: minors,
                    combinedCompleted: buckets.completed,
                    combinedInProgress: buckets.inProgress,
                    combinedPlanned: buckets.planned,
                    combinedRequired: combinedRequired,
                    academicProfile: academicProfile
                )
            }.value

            guard !Task.isCancelled else { return }

            creditLayout = AcademicsCreditLayoutSnapshot(
                programsBreakdown: breakdown,
                resolvedGraduationCreditsRequired: resolvedGraduationCreditsRequired,
                combinedRequired: combinedRequired,
                buckets: buckets,
                programCreditRows: programCreditRows
            )
            lastCreditInvalidationToken = token
        }
    }

    nonisolated static func computeBuckets(
        courseLines: [AcademicsCourseCreditLine],
        required: Int
    ) -> AcademicsCreditBuckets {
        var completed = 0
        var inProg = 0
        var planned = 0
        for line in courseLines {
            if line.isCompleted {
                completed += line.credits
            } else {
                let st = line.status ?? ""
                if st == "In Progress" || st == "In-Progress" {
                    inProg += line.credits
                } else if st == "Planned" {
                    planned += line.credits
                }
            }
        }
        let remaining = max(0, required - completed - inProg - planned)
        return AcademicsCreditBuckets(
            completed: completed,
            inProgress: inProg,
            planned: planned,
            remaining: remaining
        )
    }
}
