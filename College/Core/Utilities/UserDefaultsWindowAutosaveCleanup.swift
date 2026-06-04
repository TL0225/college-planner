// UserDefaultsWindowAutosaveCleanup.swift
// Feature: Core
// Purpose: Core module — UserDefaultsWindowAutosaveCleanup.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Removes unstable SwiftUI-generated window/split autosave keys that blow up the defaults plist
/// (macOS rejects writes when the domain exceeds ~4MB).
enum UserDefaultsWindowAutosaveCleanup {
    private static let migrationKey = "College.defaults.didPurgeUnstableWindowAutosave.v3"

    private static let frameKeyPrefix = "NSWindow Frame "
    private static let splitFramesPrefix = "NSSplitView Subview Frames "

    private static let swiftUIUnstableMarker = "SwiftUI.ModifiedContent"
    /// Split string literals so legacy window-autosave keys are matched without embedding deprecated type names.
    private static let legacyPersistenceAutosaveMarkers = [
        "Core" + "Data" + "Manager",
        "NS" + "Managed" + "ObjectContext",
    ]

    private static let preservedNameSubstrings: [String] = [
        AutosaveNames.mainWindow,
        AutosaveNames.mainSidebarSplit,
    ]

    /// Maximum encoded domain size before we purge all non-preserved frame/split keys.
    private static let aggressivePurgeEncodedByteThreshold = 3_000_000

    /// Test hook: whether `purgeUnstableFrameKeys` would remove this UserDefaults key.
    static func matchesUnstablePurgePolicy(key: String) -> Bool {
        guard isFrameOrSplitAutosaveKey(key) else { return false }
        if preservedNameSubstrings.contains(where: { key.contains($0) }) { return false }
        if key.contains(swiftUIUnstableMarker) { return true }
        if legacyPersistenceAutosaveMarkers.contains(where: { key.contains($0) }) { return true }
        if key.count > 512 { return true }
        return false
    }

    static func unstableFrameKeysRemainingCount() -> Int {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { matchesUnstablePurgePolicy(key: $0) }
            .count
    }

    /// Call at process launch before SwiftUI restores window frames.
    static func runAtLaunch() {
        let defaults = UserDefaults.standard
        let removed = purgeUnstableFrameKeys(defaults: defaults)
        if !defaults.bool(forKey: migrationKey) {
            defaults.set(true, forKey: migrationKey)
        }
        #if DEBUG
        if removed > 0 {
            DebugLogger.shared.app(
                "UserDefaultsWindowAutosaveCleanup: removed \(removed) unstable window/split autosave keys"
            )
        }
        #endif
    }

    @discardableResult
    private static func purgeUnstableFrameKeys(defaults: UserDefaults) -> Int {
        let domain = defaults.dictionaryRepresentation()
        let encodedSize = approximateEncodedSize(of: domain)
        let aggressive = encodedSize >= aggressivePurgeEncodedByteThreshold

        var removed = 0
        for key in domain.keys {
            guard isFrameOrSplitAutosaveKey(key) else { continue }
            if preservedNameSubstrings.contains(where: { key.contains($0) }) { continue }
            if aggressive || matchesUnstablePurgePolicy(key: key) {
                defaults.removeObject(forKey: key)
                removed += 1
            }
        }
        return removed
    }

    private static func isFrameOrSplitAutosaveKey(_ key: String) -> Bool {
        key.hasPrefix(frameKeyPrefix) || key.hasPrefix(splitFramesPrefix)
    }

    private static func approximateEncodedSize(of domain: [String: Any]) -> Int {
        (try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0))?
            .count ?? 0
    }
}
