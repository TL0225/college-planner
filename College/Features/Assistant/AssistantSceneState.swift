// AssistantSceneState.swift
// Feature: Assistant
// Purpose: Window-scoped scene state for assistant toolbar chrome (ADR 001).

import Foundation
import Observation

/// Assistant feature scene state. Main-window toolbar reads `toolbarProjection`.
@Observable
@MainActor
final class AssistantSceneState {
    var selectedRole: AssistantAgentRole = .academicAdvisor
    var inferenceProviderLabel: String?
    var inferenceFallbackBanner: String?

    init() {}

    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(
            activeBadgeText: "Talking to: \(selectedRole.rawValue)",
            roleSymbol: selectedRole.symbol,
            inferenceProviderLabel: inferenceProviderLabel,
            inferenceFallbackBanner: inferenceFallbackBanner
        )
    }

    struct ToolbarProjection: Equatable, Sendable {
        var activeBadgeText: String
        var roleSymbol: String
        var inferenceProviderLabel: String?
        var inferenceFallbackBanner: String?
    }

    func applyInferenceAvailability(_ availability: AssistantInferenceAvailability?) {
        inferenceProviderLabel = availability?.displayLabel
        inferenceFallbackBanner = availability?.jsonWorkerFallbackBanner
    }
}
