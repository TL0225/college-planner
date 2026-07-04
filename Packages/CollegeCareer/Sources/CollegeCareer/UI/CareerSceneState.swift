// CareerSceneState.swift
// Feature: App / Toolbar
// Owner: CareerWorkspaceView — College/Features/Career/Workspace/CareerWorkspaceView.swift

import Foundation
import Observation

/// Career feature scene state. Toolbar reads `toolbarProjection`.
@Observable
@MainActor
public final class CareerSceneState {
    public init() {}

    public var selectedView: CareerSubView = .board
    public var boardLayout: CareerBoardLayout = .kanban
    public var onBoardLayoutChange: ((CareerBoardLayout) -> Void)?

    public var toolbarProjection: ToolbarProjection {
        ToolbarProjection(selectedView: selectedView, boardLayout: boardLayout)
    }

    public struct ToolbarProjection: Equatable, Sendable {
        public var selectedView: CareerSubView
        public var boardLayout: CareerBoardLayout

        public init(selectedView: CareerSubView, boardLayout: CareerBoardLayout) {
            self.selectedView = selectedView
            self.boardLayout = boardLayout
        }
    }

    public func select(_ view: CareerSubView) {
        selectedView = view
    }

    public func setBoardLayout(_ layout: CareerBoardLayout) {
        boardLayout = layout
        onBoardLayoutChange?(layout)
    }

    public func clearHandlers() {
        onBoardLayoutChange = nil
    }
}
