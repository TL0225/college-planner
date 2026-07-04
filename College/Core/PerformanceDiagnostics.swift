// PerformanceDiagnostics.swift
// Feature: Core
// Purpose: Core module — PerformanceDiagnostics.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Darwin.Mach

/// Snapshot helpers for Settings → Performance Diagnostics (Phase 6).
enum PerformanceDiagnostics {
    /// Resident set size (RSS). NOTE: this *overcounts* the app's real memory because it
    /// includes clean/shared pages — framework code from the dyld shared cache, WebKit,
    /// Metal, and memory-mapped files (local model stores, embedding model weights). For a
    /// SwiftUI + MLX + WebKit app this is routinely 700 MB–1.5 GB even when idle, which is
    /// why the in-app gauge can read ~900 MB. Prefer ``footprintMemoryMB()`` for the number
    /// that reflects memory actually charged to this process.
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

    /// Physical memory footprint (`phys_footprint` from `TASK_VM_INFO`). This is the metric
    /// Apple uses for Activity Monitor's "Memory" column, Xcode's memory gauge, and the
    /// jetsam/termination limits — i.e. the dirty + compressed memory genuinely charged to
    /// this process, excluding shared framework/clean-file pages. This is the honest number
    /// to show the user.
    static func footprintMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    static func activeCatalogStorePathDescription() -> String {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AppDataStoreBridge.activeCatalogSchoolIDKey) == nil,
           let legacy = defaults.string(forKey: AppDataStoreBridge.legacyActiveCatalogUniversityIDKey) {
            defaults.set(legacy, forKey: AppDataStoreBridge.activeCatalogSchoolIDKey)
            defaults.removeObject(forKey: AppDataStoreBridge.legacyActiveCatalogUniversityIDKey)
        }
        let active = defaults.string(forKey: AppDataStoreBridge.activeCatalogSchoolIDKey)
        guard let id = active, !id.isEmpty else {
            return "No active catalog school"
        }
        let storePath = CollegeModelContainerFactory.catalogStoreURL(for: id).path
        if FileManager.default.fileExists(atPath: storePath) {
            return storePath
        }
        return "School \(id) (local model store not on disk)"
    }

    @MainActor
    static func localStoreDiagnosticsSummary() -> String {
        let profilePath = CollegeModelContainerFactory.profileStoreURL().path
        let profileExists = FileManager.default.fileExists(atPath: profilePath)
        let catalogOpen = AppDataStore.shared.activeCatalogContainer != nil
        let school = AppDataStore.shared.activeCatalogSchoolID ?? "none"
        return "Unified SD: \(profileExists ? "on disk" : "empty") · active catalog: \(catalogOpen ? "yes" : "no") · school=\(school)"
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
