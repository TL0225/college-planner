// CatalogSyncProgress.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSyncProgress.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Shared catalog ingest progress snapshot for onboarding, menubar, and workspace banner.
struct CatalogSyncProgress: Sendable, Equatable {
    enum Phase: String, Sendable {
        case idle
        case discovering
        case downloading
        case importing
        case indexing
        case archiving
        case succeeded
        case failed
    }

    enum Unit: String, Sendable {
        case courses
        case programs
        case requirements
        case pages
        case chunks
        case catalogs
        case bytes
        case none
    }

    let phase: Phase
    let completed: Int
    let total: Int
    let unit: Unit
    let detail: String

    static let idle = CatalogSyncProgress(phase: .idle, completed: 0, total: 0, unit: .none, detail: "")

    var fraction: Double? {
        guard total > 0, completed >= 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var fractionLabel: String {
        guard total > 0 else { return detail.isEmpty ? "Starting…" : detail }
        let unitLabel: String
        switch unit {
        case .courses: unitLabel = "Courses"
        case .programs: unitLabel = "Programs"
        case .requirements: unitLabel = "Requirements"
        case .pages: unitLabel = "Archive"
        case .chunks: unitLabel = "Search index"
        case .catalogs: unitLabel = "Catalogs"
        case .bytes: unitLabel = "Download"
        case .none: unitLabel = "Progress"
        }
        if detail.isEmpty {
            return "\(unitLabel) \(completed) / \(total)"
        }
        return "\(unitLabel) \(completed) / \(total) — \(detail)"
    }

    static func fromNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> CatalogSyncProgress? {
        let finished = (userInfo["finished"] as? Bool) == true
        if finished {
            let failed = (userInfo["failed"] as? Bool) == true
            return CatalogSyncProgress(
                phase: failed ? .failed : .succeeded,
                completed: 0,
                total: 0,
                unit: .none,
                detail: (userInfo["title"] as? String) ?? ""
            )
        }

        let completed = userInfo["completedCount"] as? Int ?? 0
        let total = userInfo["totalCount"] as? Int ?? 0
        let stage = (userInfo["stage"] as? String) ?? ""
        let title = (userInfo["title"] as? String) ?? ""
        let unit: Unit = {
            switch stage.lowercased() {
            case "courses", "course": return .courses
            case "programs", "program": return .programs
            case "requirements", "requirement": return .requirements
            case "archive": return .pages
            case "search index", "search": return .chunks
            case "catalogs", "catalog": return .catalogs
            case "download": return .bytes
            default: return .none
            }
        }()
        let phase: Phase = {
            switch unit {
            case .pages: return .archiving
            case .chunks: return .indexing
            case .bytes: return .downloading
            default: return .importing
            }
        }()
        let detail = title.isEmpty ? stage : title
        return CatalogSyncProgress(phase: phase, completed: completed, total: total, unit: unit, detail: detail)
    }
}
