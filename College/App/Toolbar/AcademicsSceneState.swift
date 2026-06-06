// AcademicsSceneState.swift
// Feature: App / Toolbar
// Owner: AcademicsView — College/Features/Academics/AcademicsView.swift

import Foundation
import Observation

/// Academics feature scene state. Toolbar reads `toolbarProjection`.
@Observable
@MainActor
final class AcademicsSceneState {
    var inspectorShown: Bool = true
    var statsSidebarShown: Bool = true
    var selectedAcademicProfileID: UUID?

    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(statsSidebarShown: statsSidebarShown)
    }

    struct ToolbarProjection: Equatable, Sendable {
        var statsSidebarShown: Bool
    }
}
