// AssistantConfirmationStyle.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantConfirmationStyle.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Tiered confirmation UI per Phase 8 HIG audit.
enum AssistantConfirmationStyle: String, Codable, Sendable {
    case none
    case inline
    case card
    case alertDestructive

    var requiresConfirmation: Bool {
        self != .none
    }
}
