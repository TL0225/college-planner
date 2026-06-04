// AcademicsToolbarState.swift
// Feature: App
// Purpose: App module — AcademicsToolbarState.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Academics toolbar display state (inspector toggle uses a `Binding` in `MainWindowToolbar`).
@Observable
@MainActor
final class AcademicsToolbarState {
    var inspectorShown: Bool = true
    /// Selected degree tab in Academics; always set to a concrete academic profile when tabs are shown.
    var selectedAcademicProfileID: UUID?
}
