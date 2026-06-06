// AcademicsSceneState.swift
// Feature: App / Toolbar
// Owner: AcademicsView — College/Features/Academics/AcademicsView.swift

import Foundation
import Observation

/// Academics feature scene state. Toolbar reads `toolbarProjection`.
@Observable
@MainActor
public final class AcademicsSceneState {
    public init() {}

    public var inspectorShown: Bool = true
    public var statsSidebarShown: Bool = true
    public var selectedAcademicProfileID: UUID?

    public var toolbarProjection: ToolbarProjection {
        ToolbarProjection(statsSidebarShown: statsSidebarShown)
    }

    public struct ToolbarProjection: Equatable, Sendable {
        public var statsSidebarShown: Bool

        public init(statsSidebarShown: Bool) {
            self.statsSidebarShown = statsSidebarShown
        }
    }
}
