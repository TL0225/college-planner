// LMSPortalConfiguration.swift
// Feature: App
// Purpose: App module — LMSProvider.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Supported learning platforms for the in-app portal tab (single active provider + per-provider URLs).
enum LMSProvider: String, CaseIterable, Identifiable, Hashable {
    case brightspace = "Brightspace"
    case canvas = "Canvas"
    case moodle = "Moodle"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brightspace: return "safari.fill"
        case .canvas: return "rectangle.split.3x3.fill"
        case .moodle: return "graduationcap.fill"
        }
    }

    /// Placeholder copy for Settings; no institution is implied until the user enters a URL.
    var portalURLPlaceholder: String {
        switch self {
        case .brightspace:
            return "https://brightspace.yourschool.edu"
        case .canvas:
            return "https://canvas.yourschool.edu"
        case .moodle:
            return "https://moodle.yourschool.edu"
        }
    }

    fileprivate var portalURLStorageKey: String {
        "lms.portalURL.\(rawValue)"
    }
}

enum LMSPortalConfiguration {
    static let activeProviderKey = "lms.activeProvider"

    /// Generic user-facing name for the in-app LMS portal (not the active provider brand).
    static var lmsDisplayName: String {
        String(localized: "lms.display_name", defaultValue: "Learning Management System")
    }

    static var lmsDisplayNameShort: String {
        String(localized: "lms.display_name.short", defaultValue: "LMS")
    }

    /// Legacy global portal-URL key retained for backward compatibility (read as a fallback and
    /// mirrored to when the active provider is Brightspace). New writes also use per-provider keys.
    private static let legacyLMSPortalKey = "brightspace.portalURL"
    private static let pendingLoadPortalKey = LMSStorageKeys.pendingLoadPortalOnNextAppear

    /// True when onboarding selected an LMS or the user configured / visited a portal.
    static func isLMSTabEnabled() -> Bool {
        let onboardingSelection = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.selectedLMSKey) ?? []
        if !onboardingSelection.isEmpty { return true }

        for provider in LMSProvider.allCases where !portalURLString(for: provider).isEmpty {
            return true
        }

        let legacy = UserDefaults.standard.string(forKey: legacyLMSPortalKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return true }

        if let lastVisited = UserDefaults.standard.string(forKey: LMSStorageKeys.lastVisitedURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !lastVisited.isEmpty {
            return true
        }

        return false
    }

    static func resolvedActiveProvider() -> LMSProvider? {
        guard isLMSTabEnabled() else { return nil }

        if let raw = UserDefaults.standard.string(forKey: activeProviderKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let provider = LMSProvider(rawValue: raw) {
            return provider
        }

        if let onboarding = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.selectedLMSKey)?.first,
           let provider = lmsProvider(matchingOnboardingLabel: onboarding) {
            return provider
        }

        return .brightspace
    }

    /// Sidebar / dock label for the unified LMS page.
    static var sidebarDisplayTitle: String {
        if let onboarding = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.selectedLMSKey)?.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !onboarding.isEmpty {
            return onboarding
        }
        if let raw = UserDefaults.standard.string(forKey: activeProviderKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return resolvedActiveProvider()?.rawValue ?? "LMS"
    }

    static func resolvedPortalURL() -> URL? {
        guard let provider = resolvedActiveProvider() else { return nil }

        if provider == .brightspace {
            let legacy = UserDefaults.standard.string(forKey: legacyLMSPortalKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty, let url = URL(string: legacy) { return url }
        }

        let stored = UserDefaults.standard.string(forKey: provider.portalURLStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty, let url = URL(string: stored) { return url }

        return nil
    }

    static func applyOnboardingLMSSelection(_ providers: [String]) {
        let trimmed = providers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: activeProviderKey)
            UserDefaults.standard.set(false, forKey: pendingLoadPortalKey)
            return
        }

        if let first = trimmed.first, let provider = lmsProvider(matchingOnboardingLabel: first) {
            setActiveProvider(provider)
        } else if let first = trimmed.first {
            UserDefaults.standard.set(first, forKey: activeProviderKey)
        }
    }

    private static func lmsProvider(matchingOnboardingLabel label: String) -> LMSProvider? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return LMSProvider(rawValue: normalized)
    }

    static func setActiveProvider(_ provider: LMSProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: activeProviderKey)
    }

    static func setPortalURLString(_ raw: String?, for provider: LMSProvider) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = provider.portalURLStorageKey
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }

        if provider == .brightspace {
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: legacyLMSPortalKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: legacyLMSPortalKey)
            }
        }
    }

    static func portalURLString(for provider: LMSProvider) -> String {
        if provider == .brightspace {
            let legacy = UserDefaults.standard.string(forKey: legacyLMSPortalKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty { return legacy }
        }
        return UserDefaults.standard.string(forKey: provider.portalURLStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Whether launch should spin up a WKWebView for the LMS portal (Phase 2 P0).
    /// Skips preload when the user has never configured or visited the portal.
    static func shouldPreloadPortalAtLaunch() -> Bool {
        guard isLMSTabEnabled() else { return false }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: pendingLoadPortalKey) { return true }
        if let lastVisited = defaults.string(forKey: LMSStorageKeys.lastVisitedURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !lastVisited.isEmpty {
            return true
        }
        guard let provider = resolvedActiveProvider() else { return false }
        return !portalURLString(for: provider).isEmpty
    }
}
