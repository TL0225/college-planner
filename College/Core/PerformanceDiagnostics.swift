// PerformanceDiagnostics.swift
// Feature: Core
// Purpose: Core module — PerformanceDiagnostics.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Darwin.Mach

/// Snapshot helpers for Settings → Performance Diagnostics (Phase 6).
enum PerformanceDiagnostics {
    static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    static func activeCatalogStorePathDescription() -> String {
        let active = UserDefaults.standard.string(forKey: "catalog.activeSchoolID")
            ?? UserDefaults.standard.string(forKey: "catalog.activeUniversityID")
        guard let id = active, !id.isEmpty else {
            return "No active catalog school"
        }
        let storePath = CollegeModelContainerFactory.catalogStoreURL(for: id).path
        if FileManager.default.fileExists(atPath: storePath) {
            return storePath
        }
        let legacyRoot = CollegeModelContainerFactory.catalogStoreDirectory(for: id)
        let legacySQLite = legacyRoot.appendingPathComponent("catalog.sqlite").path
        if FileManager.default.fileExists(atPath: legacySQLite) {
            return legacySQLite
        }
        return "School \(id) (path not on disk)"
    }

    @MainActor
    static func localStoreDiagnosticsSummary() -> String {
        let profilePath = CollegeModelContainerFactory.profileStoreURL().path
        let profileExists = FileManager.default.fileExists(atPath: profilePath)
        let catalogOpen = AppDataStore.shared.activeCatalogContainer != nil
        let school = AppDataStore.shared.activeCatalogSchoolID ?? "none"
        return "Profile SD: \(profileExists ? "on disk" : "empty") · Catalog container: \(catalogOpen ? "open" : "closed") · school=\(school)"
    }

    static var llmIdleTimeoutSeconds: Int {
        let stored = UserDefaults.standard.double(forKey: "assistant.llm.idleTimeoutSeconds")
        return stored > 0 ? Int(stored) : 120
    }

    static var freeMemoryBetweenSessionsEnabled: Bool {
        let key = "assistant.llm.freeMemoryBetweenSessions"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    @MainActor
    static func lastMemoryPressureEventDescription() -> String {
        let handler = MemoryPressureHandler.shared
        guard let at = handler.lastMemoryPressureEventAt else { return "None recorded" }
        let kind = handler.lastMemoryPressureEventKind ?? "unknown"
        return "\(kind) · \(at.formatted(date: .abbreviated, time: .standard))"
    }
}
