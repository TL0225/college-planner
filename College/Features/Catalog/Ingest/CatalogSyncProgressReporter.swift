// CatalogSyncProgressReporter.swift
// Feature: Catalog
// Purpose: Single write API for catalog sync progress across menu bar, activity center, and hooks.

import Foundation

enum CatalogSyncStage: String, Sendable {
    case idle
    case verifyingPlatform
    case discoveringCatalogs
    case scrapingPrograms
    case evaluatingQuality
    case savingPrograms
    case importingCourses
    case archivingPDF
}

enum CatalogSyncTerminal: Sendable, Equatable {
    case succeeded(summary: String)
    case skipped(reason: String)
    case failed(message: String)
}

extension Notification.Name {
    static let catalogSyncProgressDidUpdate = Notification.Name("catalog.syncProgressDidUpdate")
    static let catalogSyncPhaseACommitted = Notification.Name("catalog.syncPhaseACommitted")
}

/// Fans out catalog sync snapshots to menubar notifier, background activity center, and ingest hooks.
@MainActor
struct CatalogSyncProgressReporter {
    let activityID: String

    static let main = CatalogSyncProgressReporter(activityID: "catalog.import")
    static let courses = CatalogSyncProgressReporter(activityID: "catalog.courses")
    static let vectorIndex = CatalogSyncProgressReporter(activityID: "catalog.vector_index")
    static let archive = CatalogSyncProgressReporter(activityID: "catalog.archive")

    private static var sessionHooks: CatalogBackgroundSyncRunner.Hooks?

    static func beginSession(hooks: CatalogBackgroundSyncRunner.Hooks?) {
        sessionHooks = hooks
    }

    static func endSession() {
        sessionHooks = nil
    }

    static func emitPhaseACommitted(
        universityID: UUID,
        programCount: Int,
        hooks: CatalogBackgroundSyncRunner.Hooks? = nil
    ) {
        let resolvedHooks = hooks ?? sessionHooks
        resolvedHooks?.onPhaseACommitted?(universityID, programCount)
        NotificationCenter.default.post(
            name: .catalogSyncPhaseACommitted,
            object: nil,
            userInfo: [
                "universityID": universityID.uuidString,
                "programCount": programCount,
            ]
        )
    }

    func reportProgress(
        _ progress: CatalogSyncProgress,
        hooks: CatalogBackgroundSyncRunner.Hooks? = nil
    ) {
        let resolvedHooks = hooks ?? Self.sessionHooks
        publishSnapshot(progress, schoolName: nil)

        switch progress.phase {
        case .idle, .succeeded, .failed, .skipped:
            break
        case .discovering:
            resolvedHooks?.onVisualPhase?(.discovering)
            if let fraction = progress.fraction {
                resolvedHooks?.onProgress?(fraction, progress.detail)
            }
        case .downloading:
            resolvedHooks?.onVisualPhase?(.downloading)
            if let fraction = progress.fraction {
                resolvedHooks?.onProgress?(fraction, progress.detail)
            }
        case .verifyingPlatform, .evaluatingQuality, .importing, .indexing, .archiving:
            resolvedHooks?.onVisualPhase?(.importing)
            if let fraction = progress.fraction {
                resolvedHooks?.onProgress?(fraction, progress.detail)
            }
        }

        switch progress.phase {
        case .idle, .succeeded, .failed, .skipped:
            return
        default:
            break
        }

        if let fraction = progress.fraction {
            CatalogMenuBarProgressNotifier.postInProgress(
                fraction: fraction,
                title: progress.fractionLabel,
                indeterminate: false,
                activityID: activityID
            )
            BackgroundActivityReporter.running(
                id: activityID,
                domain: .catalog,
                title: progress.detail.isEmpty ? progress.fractionLabel : progress.detail,
                detail: progress.fractionLabel,
                fraction: fraction,
                indeterminate: false
            )
        } else {
            CatalogMenuBarProgressNotifier.postInProgress(
                fraction: 0,
                title: progress.fractionLabel,
                indeterminate: true,
                activityID: activityID
            )
            BackgroundActivityReporter.running(
                id: activityID,
                domain: .catalog,
                title: progress.fractionLabel,
                indeterminate: true
            )
        }
    }

    func reportStage(
        _ stage: CatalogSyncStage,
        completed: Int = 0,
        total: Int = 0,
        detail: String = "",
        hooks: CatalogBackgroundSyncRunner.Hooks? = nil
    ) {
        reportProgress(
            CatalogSyncProgress(
                phase: phase(for: stage),
                completed: completed,
                total: total,
                unit: unit(for: stage),
                detail: detail
            ),
            hooks: hooks
        )
    }

    func reportTerminal(
        _ terminal: CatalogSyncTerminal,
        hooks: CatalogBackgroundSyncRunner.Hooks? = nil
    ) {
        let resolvedHooks = hooks ?? Self.sessionHooks
        resolvedHooks?.onSyncTerminal?(terminal)

        switch terminal {
        case .succeeded(let summary):
            let progress = CatalogSyncProgress(
                phase: .succeeded,
                completed: 0,
                total: 0,
                unit: .none,
                detail: summary
            )
            publishSnapshot(progress, schoolName: nil)
            CatalogMenuBarProgressNotifier.postSucceeded(
                title: summary,
                summary: summary,
                activityID: activityID
            )
            ensureActivityVisible(title: summary)
            BackgroundActivityReporter.finish(id: activityID, succeeded: true, summary: summary)

        case .skipped(let reason):
            let progress = CatalogSyncProgress(
                phase: .skipped,
                completed: 0,
                total: 0,
                unit: .none,
                detail: reason
            )
            publishSnapshot(progress, schoolName: nil)
            CatalogMenuBarProgressNotifier.postSkipped(message: reason, activityID: activityID)
            ensureActivityVisible(title: reason)
            BackgroundActivityReporter.finish(id: activityID, succeeded: true, summary: reason)

        case .failed(let message):
            let progress = CatalogSyncProgress(
                phase: .failed,
                completed: 0,
                total: 0,
                unit: .none,
                detail: message
            )
            publishSnapshot(progress, schoolName: nil)
            CatalogMenuBarProgressNotifier.postFailed(message: message, activityID: activityID)
            ensureActivityVisible(title: message)
            BackgroundActivityReporter.finish(id: activityID, succeeded: false, summary: message)
        }
    }

    /// Terminal updates must upsert first — `BackgroundActivityCenter.finish` is a no-op when
    /// no row exists yet (e.g. unit tests that call `reportTerminal` without prior progress).
    private func ensureActivityVisible(title: String) {
        BackgroundActivityReporter.running(
            id: activityID,
            domain: .catalog,
            title: title,
            indeterminate: false
        )
    }

    private func publishSnapshot(_ progress: CatalogSyncProgress, schoolName: String?) {
        var userInfo: [AnyHashable: Any] = [
            "phase": progress.phase.rawValue,
            "detail": progress.detail,
            "completed": progress.completed,
            "total": progress.total,
            "unit": progress.unit.rawValue,
            "activityID": activityID,
        ]
        if let schoolName {
            userInfo["schoolName"] = schoolName
        }
        NotificationCenter.default.post(
            name: .catalogSyncProgressDidUpdate,
            object: nil,
            userInfo: userInfo
        )
    }

    private func phase(for stage: CatalogSyncStage) -> CatalogSyncProgress.Phase {
        switch stage {
        case .idle: return .idle
        case .verifyingPlatform: return .verifyingPlatform
        case .discoveringCatalogs: return .discovering
        case .scrapingPrograms, .savingPrograms: return .importing
        case .evaluatingQuality: return .evaluatingQuality
        case .importingCourses: return .importing
        case .archivingPDF: return .archiving
        }
    }

    private func unit(for stage: CatalogSyncStage) -> CatalogSyncProgress.Unit {
        switch stage {
        case .scrapingPrograms, .savingPrograms: return .programs
        case .importingCourses: return .courses
        case .archivingPDF: return .pages
        default: return .none
        }
    }
}
