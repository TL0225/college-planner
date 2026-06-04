// OnboardingPreferenceBridge.swift
// Feature: App
// Purpose: App module — OnboardingPreferenceBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum OnboardingPreferenceBridge {
    static let completedKey = "onboarding.completed.v1"
    static let selectedLMSKey = "onboarding.selectedLMS.v1"
    static let selectedWidgetsKey = "onboarding.selectedWidgets.v1"
    static let academicDraftKey = "onboarding.academicDraft.v1"
    static let catalogSyncInFlightKey = "onboarding.catalogSyncInFlight.v1"
    /// After onboarding, Overview may show a one-time prompt to run a full catalog + requirements scrape.
    static let showDeepCatalogPromptKey = "overview.showDeepCatalogPrompt.v1"
    /// User finished a full ModernCampus scrape (requirements + courses); hide the prompt permanently.
    static let deepCatalogScrapeCompletedKey = "catalog.deepScrapeCompleted.v1"
    /// When `true`, `importSchoolCatalog` runs background LLM parsing for complex prerequisites (heavy memory).
    /// Default is off (`UserDefaults.bool` is false when unset).
    static let catalogPrerequisiteLLMEnabledKey = "catalog.prerequisiteLLMEnabled.v1"
    static var isCatalogPrerequisiteLLMEnabled: Bool {
        UserDefaults.standard.bool(forKey: catalogPrerequisiteLLMEnabledKey)
    }
    static let pendingLMSConnectKey = "onboarding.pendingLMSConnect.v1"
    static let dashboardWidgetsKey = "dashboard.widgets.v1"

    static let brightspaceProvider = "Brightspace"

    static let defaultDashboardWidgets: Set<String> = [
        "Upcoming Assignments",
        "Next Class",
        "GPA Snapshot",
        "Deadlines"
    ]

    static func resolvedDashboardWidgets(from stored: [String]?) -> Set<String> {
        guard let stored, !stored.isEmpty else {
            return defaultDashboardWidgets
        }
        return Set(stored)
    }

    static func shouldOpenBrightspace(from selectedProviders: [String]) -> Bool {
        selectedProviders.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(brightspaceProvider, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    static func preferredConnectDestination(from selectedProviders: [String]) -> AppPage {
        if shouldOpenBrightspace(from: selectedProviders) {
            return .brightspace
        }
        return .profile
    }

    /// Clears onboarding / first-run flags so the next launch shows onboarding (UserDefaults, not local store).
    static func resetOnboardingState() {
        let keys = [
            completedKey,
            selectedLMSKey,
            selectedWidgetsKey,
            academicDraftKey,
            catalogSyncInFlightKey,
            pendingLMSConnectKey,
            dashboardWidgetsKey,
            showDeepCatalogPromptKey,
            deepCatalogScrapeCompletedKey,
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
