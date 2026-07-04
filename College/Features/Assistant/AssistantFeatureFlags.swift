// AssistantFeatureFlags.swift
// Feature: Assistant
// Purpose: Gradual rollout flags for assistant capabilities.

import Foundation

enum AssistantFeatureFlags {
    static let careerExplorationKey = "assistant.careerExploration.enabled"
    static let degreePolicyLookupKey = "assistant.degreePolicyLookup.enabled"
    static let webGovernanceStrictKey = "assistant.webGovernance.strict"

    static var careerExplorationEnabled: Bool {
        UserDefaults.standard.object(forKey: careerExplorationKey) != nil
            ? UserDefaults.standard.bool(forKey: careerExplorationKey)
            : true
    }

    static var degreePolicyLookupEnabled: Bool {
        UserDefaults.standard.object(forKey: degreePolicyLookupKey) != nil
            ? UserDefaults.standard.bool(forKey: degreePolicyLookupKey)
            : true
    }

    static var webGovernanceStrict: Bool {
        UserDefaults.standard.bool(forKey: webGovernanceStrictKey)
    }
}
