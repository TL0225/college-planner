// CareerSceneState.swift
// Feature: App / Toolbar
// Owner: CareerWorkspaceView — College/Features/Career/CareerWorkspaceView.swift

import Foundation
import Observation

/// Career feature scene state. Toolbar reads `toolbarProjection`.
@Observable
@MainActor
final class CareerSceneState {
    var selectedView: CareerSubView = .board
    var boardLayout: CareerBoardLayout = .kanban
    var onBoardLayoutChange: ((CareerBoardLayout) -> Void)?

    var toolbarProjection: ToolbarProjection {
        ToolbarProjection(selectedView: selectedView, boardLayout: boardLayout)
    }

    struct ToolbarProjection: Equatable, Sendable {
        var selectedView: CareerSubView
        var boardLayout: CareerBoardLayout
    }

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
