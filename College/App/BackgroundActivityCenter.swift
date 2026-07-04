// BackgroundActivityCenter.swift
// Feature: App
// Purpose: Single registry for in-flight background work shown in the menu bar panel.

import Foundation
import Observation

enum BackgroundActivityDomain: String, CaseIterable, Sendable, Identifiable {
    case catalog
    case catalogPurge
    case careerJobBoard
    case careerResume
    case aiModel
    case vaultIndexing
    case academicCalendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .catalog:
            return String(localized: "background.domain.catalog", defaultValue: "Catalog")
        case .catalogPurge:
            return String(localized: "background.domain.catalog_purge", defaultValue: "Catalog reset")
        case .careerJobBoard:
            return String(localized: "background.domain.career_jobboard", defaultValue: "Career · Job boards")
        case .careerResume:
            return String(localized: "background.domain.career_resume", defaultValue: "Career · Resumes")
        case .aiModel:
            return String(localized: "background.domain.ai_model", defaultValue: "AI model")
        case .vaultIndexing:
            return String(localized: "background.domain.vault_indexing", defaultValue: "Assistant · Documents")
        case .academicCalendar:
            return String(localized: "background.domain.academic_calendar", defaultValue: "Calendar")
        }
    }

    var systemImage: String {
        switch self {
        case .catalog, .catalogPurge: return "books.vertical.fill"
        case .careerJobBoard: return "briefcase.fill"
        case .careerResume: return "doc.text.fill"
        case .aiModel: return "brain.head.profile"
        case .vaultIndexing: return "doc.text.magnifyingglass"
        case .academicCalendar: return "calendar"
        }
    }

    var sortOrder: Int {
        switch self {
        case .catalog: return 0
        case .catalogPurge: return 1
        case .careerJobBoard: return 2
        case .careerResume: return 3
        case .aiModel: return 4
        case .vaultIndexing: return 5
        case .academicCalendar: return 6
        }
    }
}

struct BackgroundActivityItem: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case running
        case succeeded(String)
        case failed(String)
    }

    let id: String
    let domain: BackgroundActivityDomain
    var title: String
    var detail: String?
    var fraction: Double?
    var indeterminate: Bool
    var phase: Phase
    var updatedAt: Date

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var displayFraction: Double? {
        guard !indeterminate, let fraction, fraction.isFinite, fraction > 0 else { return nil }
        return min(1, max(0, fraction))
    }

    var percentText: String? {
        guard let displayFraction else { return nil }
        return "\(Int((displayFraction * 100).rounded()))%"
    }
}

private struct BackgroundActivityProgressPayload: Sendable {
    let finished: Bool
    let failed: Bool
    let title: String
    let fraction: Double?
    let indeterminate: Bool
    let message: String?
    let summary: String?
    let completedCount: Int?
    let totalCount: Int?
    let stage: String?
    let activityID: String?

    init(userInfo: [AnyHashable: Any]) {
        finished = (userInfo["finished"] as? Bool) == true
        failed = (userInfo["failed"] as? Bool) == true
        title = (userInfo["title"] as? String) ?? ""
        fraction = userInfo["fraction"] as? Double
        indeterminate = (userInfo["indeterminate"] as? Bool) == true
        message = userInfo["message"] as? String
        summary = userInfo["summary"] as? String
        completedCount = userInfo["completedCount"] as? Int
        totalCount = userInfo["totalCount"] as? Int
        stage = userInfo["stage"] as? String
        activityID = userInfo["activityID"] as? String
    }
}

/// Central source of truth for menu-bar background activity UI.
@Observable
@MainActor
final class BackgroundActivityCenter {
    static let shared = BackgroundActivityCenter()

    private(set) var activities: [BackgroundActivityItem] = []

    @ObservationIgnored private var importObserver: NSObjectProtocol?
    @ObservationIgnored private var purgeObserver: NSObjectProtocol?
    @ObservationIgnored private var dismissalTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    nonisolated deinit {
        MainActor.assumeIsolated {
            if let importObserver {
                NotificationCenter.default.removeObserver(importObserver)
            }
            if let purgeObserver {
                NotificationCenter.default.removeObserver(purgeObserver)
            }
            for task in dismissalTasks.values {
                task.cancel()
            }
        }
    }

    var hasRunningWork: Bool {
        activities.contains(where: \.isRunning)
    }

    var menuBarTooltip: String {
        let running = activities.filter(\.isRunning)
        guard !running.isEmpty else {
            return String(localized: "menubar.tooltip.idle", defaultValue: "College")
        }
        if running.count == 1, let only = running.first {
            if let pct = only.percentText {
                return "\(only.title) — \(pct)"
            }
            return only.title
        }
        return String(
            format: String(
                localized: "background.tooltip.multiple",
                defaultValue: "%d background tasks running"
            ),
            running.count
        )
    }

    var groupedRunningActivities: [(domain: BackgroundActivityDomain, items: [BackgroundActivityItem])] {
        let running = activities.filter(\.isRunning)
        return BackgroundActivityDomain.allCases.compactMap { domain in
            let items = running
                .filter { $0.domain == domain }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard !items.isEmpty else { return nil }
            return (domain, items)
        }
    }

    /// Stable, single-pass rows for the menu bar panel. Activity ids stay fixed when
    /// phase changes so SwiftUI can update rows in place instead of reshuffling lists.
    enum MenuBarActivityRow: Identifiable, Equatable {
        case domainHeader(BackgroundActivityDomain)
        case activity(BackgroundActivityItem)

        var id: String {
            switch self {
            case .domainHeader(let domain):
                return "menubar.header.\(domain.id)"
            case .activity(let item):
                return item.id
            }
        }
    }

    var menuBarActivityRows: [MenuBarActivityRow] {
        let sorted = activities.sorted { lhs, rhs in
            if lhs.domain.sortOrder != rhs.domain.sortOrder {
                return lhs.domain.sortOrder < rhs.domain.sortOrder
            }
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var rows: [MenuBarActivityRow] = []
        var lastDomain: BackgroundActivityDomain?
        for item in sorted {
            if item.domain != lastDomain {
                rows.append(.domainHeader(item.domain))
                lastDomain = item.domain
            }
            rows.append(.activity(item))
        }
        return rows
    }

    func startObservingProgressNotifications() {
        guard importObserver == nil else { return }

        importObserver = NotificationCenter.default.addObserver(
            forName: .collegeCatalogBackgroundImportProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let payload = BackgroundActivityProgressPayload(userInfo: note.userInfo ?? [:])
            Task { @MainActor in
                self?.applyCatalogImport(payload)
            }
        }

        purgeObserver = NotificationCenter.default.addObserver(
            forName: .collegeCatalogScrapePurgeProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let payload = BackgroundActivityProgressPayload(userInfo: note.userInfo ?? [:])
            Task { @MainActor in
                self?.applyCatalogPurge(payload)
            }
        }

        if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
            upsertRunning(
                id: Self.catalogImportID,
                domain: .catalog,
                title: String(
                    localized: "menubar.catalog.resuming",
                    defaultValue: "Catalog import in progress…"
                ),
                indeterminate: true
            )
        }
    }

    func resetForTesting() {
        for task in dismissalTasks.values { task.cancel() }
        dismissalTasks.removeAll()
        activities.removeAll()
    }

    // MARK: - Public reporter API

    func upsertRunning(
        id: String,
        domain: BackgroundActivityDomain,
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        indeterminate: Bool = false
    ) {
        cancellationTask(for: id)?.cancel()
        dismissalTasks[id] = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index].title = trimmedTitle.isEmpty ? activities[index].title : trimmedTitle
            activities[index].detail = trimmedDetail?.isEmpty == false ? trimmedDetail : activities[index].detail
            activities[index].fraction = fraction
            activities[index].indeterminate = indeterminate
            activities[index].phase = .running
            activities[index].updatedAt = .now
            return
        }

        activities.append(
            BackgroundActivityItem(
                id: id,
                domain: domain,
                title: trimmedTitle.isEmpty ? domain.displayName : trimmedTitle,
                detail: trimmedDetail?.isEmpty == false ? trimmedDetail : nil,
                fraction: fraction,
                indeterminate: indeterminate,
                phase: .running,
                updatedAt: .now
            )
        )
    }

    func finish(id: String, succeeded: Bool, summary: String, autoDismissAfter seconds: TimeInterval = 8) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        activities[index].phase = succeeded
            ? .succeeded(trimmed.isEmpty ? "Finished" : trimmed)
            : .failed(trimmed.isEmpty ? "Failed" : trimmed)
        activities[index].fraction = succeeded ? 1 : activities[index].fraction
        activities[index].indeterminate = false
        activities[index].updatedAt = .now

        cancellationTask(for: id)?.cancel()
        dismissalTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            activities.removeAll { $0.id == id }
            dismissalTasks[id] = nil
        }
    }

    func remove(id: String) {
        cancellationTask(for: id)?.cancel()
        dismissalTasks[id] = nil
        activities.removeAll { $0.id == id }
    }

    static let catalogImportID = "catalog.import"
    static let catalogCoursesID = "catalog.courses"
    static let catalogVectorIndexID = "catalog.vector_index"
    static let catalogArchiveID = "catalog.archive"
    static let catalogPurgeID = "catalog.purge"

    nonisolated static func jobBoardActivityID(slug: String) -> String {
        "career.jobboard.\(slug.lowercased())"
    }

    nonisolated static func resumeActivityID(documentID: UUID) -> String {
        "career.resume.\(documentID.uuidString)"
    }

    nonisolated static func aiModelActivityID(modelName: String) -> String {
        "ai.model.\(modelName.lowercased())"
    }

    nonisolated static func vaultDocumentActivityID(documentID: UUID) -> String {
        "vault.index.\(documentID.uuidString)"
    }

    nonisolated static func academicCalendarActivityID(schoolID: String) -> String {
        "calendar.scrape.\(schoolID.lowercased())"
    }

    nonisolated static func academicCalendarActivityID(configID: String) -> String {
        "calendar.scrape.\(configID.lowercased())"
    }

    nonisolated static func icsSubscriptionActivityID(subscriptionID: String) -> String {
        "ics.subscription.\(subscriptionID.lowercased())"
    }

    nonisolated static func programRequirementsActivityID(programURL: String) -> String {
        "catalog.program_requirements.\(programURL.lowercased())"
    }

    // MARK: - Catalog notification bridge

    private func applyCatalogImport(_ payload: BackgroundActivityProgressPayload) {
        let activityID = payload.activityID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? payload.activityID!
            : Self.catalogImportID

        if payload.finished {
            if payload.failed {
                let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(
                    id: activityID,
                    succeeded: false,
                    summary: message?.isEmpty == false
                        ? message!
                        : String(
                            localized: "menubar.catalog.failed_generic",
                            defaultValue: "Catalog import failed."
                        )
                )
            } else {
                let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(
                    id: activityID,
                    succeeded: true,
                    summary: summary?.isEmpty == false
                        ? summary!
                        : String(
                            localized: "menubar.catalog.succeeded_generic",
                            defaultValue: "Catalog import finished."
                        )
                )
            }
            return
        }

        let composed = composeCatalogTitle(payload)
        upsertRunning(
            id: activityID,
            domain: .catalog,
            title: composed.title,
            detail: composed.detail,
            fraction: payload.fraction,
            indeterminate: payload.indeterminate || payload.fraction == nil
        )
    }

    private func applyCatalogPurge(_ payload: BackgroundActivityProgressPayload) {
        if payload.finished {
            if payload.failed {
                let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(
                    id: Self.catalogPurgeID,
                    succeeded: false,
                    summary: message?.isEmpty == false
                        ? message!
                        : String(
                            localized: "menubar.catalog_purge.failed_generic",
                            defaultValue: "Catalog reset did not finish cleanly."
                        )
                )
            } else {
                let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
                finish(
                    id: Self.catalogPurgeID,
                    succeeded: true,
                    summary: summary?.isEmpty == false
                        ? summary!
                        : String(
                            localized: "menubar.catalog_purge.succeeded_generic",
                            defaultValue: "Catalog scrape data cleared."
                        )
                )
            }
            return
        }

        let composed = composeCatalogTitle(payload)
        upsertRunning(
            id: Self.catalogPurgeID,
            domain: .catalogPurge,
            title: composed.title,
            detail: composed.detail,
            fraction: payload.fraction,
            indeterminate: payload.indeterminate || payload.fraction == nil
        )
    }

    private func composeCatalogTitle(_ payload: BackgroundActivityProgressPayload) -> (title: String, detail: String?) {
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let completed = payload.completedCount,
           completed >= 0,
           let total = payload.totalCount,
           total > 0 {
            let stage = payload.stage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let countLabel = (stage?.isEmpty == false)
                ? "\(stage!) \(completed) / \(total)"
                : "\(completed) / \(total)"
            if title.isEmpty {
                return (countLabel, nil)
            }
            return (title, countLabel)
        }
        if title.isEmpty {
            return (
                String(
                    localized: "menubar.catalog.importing",
                    defaultValue: "Catalog import in progress…"
                ),
                nil
            )
        }
        return (title, nil)
    }

    private func cancellationTask(for id: String) -> Task<Void, Never>? {
        dismissalTasks[id]
    }
}

@MainActor
enum BackgroundActivityReporter {
    static func running(
        id: String,
        domain: BackgroundActivityDomain,
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        indeterminate: Bool = false
    ) {
        BackgroundActivityCenter.shared.upsertRunning(
            id: id,
            domain: domain,
            title: title,
            detail: detail,
            fraction: fraction,
            indeterminate: indeterminate
        )
    }

    static func finish(id: String, succeeded: Bool, summary: String) {
        BackgroundActivityCenter.shared.finish(id: id, succeeded: succeeded, summary: summary)
    }

    static func remove(id: String) {
        BackgroundActivityCenter.shared.remove(id: id)
    }
}
