// LMSStorageKeys.swift
// Feature: LMS
// Purpose: Shared UserDefaults keys for the in-app LMS portal (nonisolated for settings and config reads).

import Foundation

enum LMSStorageKeys {
    static let lastVisitedURL = "lms.lastVisitedURL"
    static let pendingLoadPortalOnNextAppear = "lms.pendingLoadPortalOnNextAppear"
    static let savePassword = "lms.savePassword"
    static let allowPageContextExtraction = "lms.allowPageContextExtraction"

    /// Legacy `brightspace.*` keys mapped to their current `lms.*` equivalents.
    /// The global portal-URL key intentionally remains `brightspace.portalURL`; it is read as the
    /// legacy fallback by `LMSPortalConfiguration` alongside the per-provider `lms.portalURL.<Provider>` keys.
    private static let legacyKeyPairs: [(legacy: String, current: String)] = [
        ("brightspace.lastVisitedURL", lastVisitedURL),
        ("brightspace.pendingLoadPortalOnNextAppear", pendingLoadPortalOnNextAppear),
        ("brightspace.savePassword", savePassword),
        ("brightspace.allowPageContextExtraction", allowPageContextExtraction),
    ]

    /// One-time copy of legacy `brightspace.*` defaults to their `lms.*` equivalents.
    /// Safe to call on every launch: only copies when the legacy key exists and the new key is unset.
    static func migrateLegacyDefaultsIfNeeded(_ defaults: UserDefaults = .standard) {
        for pair in legacyKeyPairs {
            guard defaults.object(forKey: pair.current) == nil,
                  let value = defaults.object(forKey: pair.legacy) else { continue }
            defaults.set(value, forKey: pair.current)
        }
    }
}
