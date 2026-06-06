// AppToolbarStore.swift
// Feature: App / Toolbar
// Purpose: Cross-tab toolbar state only (ADR 001). Never page-specific display fields.

import Foundation
import Observation

@Observable
@MainActor
final class AppToolbarStore: CrossTabToolbarState {
    // MARK: - Cross-tab State
    // Reserved for shell-level toolbar concerns shared across tabs.
    // Page display state lives on feature scene types (e.g. CalendarSceneState).
}
