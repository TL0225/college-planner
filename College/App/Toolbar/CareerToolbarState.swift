// CareerToolbarState.swift
// Feature: App
// Purpose: App module — CareerToolbarState.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Career tab window-toolbar state (owned by `CareerWorkspaceView`).
@Observable
@MainActor
final class CareerToolbarState {
    var selectedView: CareerSubView = .board
    var boardLayout: CareerBoardLayout = .kanban
    var onBoardLayoutChange: ((CareerBoardLayout) -> Void)?

    func select(_ view: CareerSubView) {
        selectedView = view
    }

    func setBoardLayout(_ layout: CareerBoardLayout) {
        boardLayout = layout
        onBoardLayoutChange?(layout)
    }

    func clearHandlers() {
        onBoardLayoutChange = nil
    }
}
