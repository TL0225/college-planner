// CrossTabToolbarState.swift
// Feature: App / Toolbar
// Purpose: Type-level boundary for cross-tab toolbar store (ADR 001).

import Foundation

/// Cross-tab toolbar state only. Page display state belongs on feature scene types.
@MainActor
protocol CrossTabToolbarState: AnyObject {}
