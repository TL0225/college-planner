// AcademicsToolbarContent.swift
// Feature: App / Toolbar

import CollegeAcademics
import SwiftUI

struct AcademicsToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher
    let academicsScene: AcademicsSceneState
    let collegePersistence: CollegePersistence
    @Binding var academicsInspectorPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(id: "academics.degreeScope", placement: .principal) {
            HStack(spacing: 8) {
                AcademicsDegreeScopeToolbar(
                    collegePersistence: collegePersistence,
                    academicsScene: academicsScene
                )
                AcademicsToolbarAddProfileButton(
                    collegePersistence: collegePersistence,
                    academicsScene: academicsScene
                )
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "academics.sidebarToggle", placement: .primaryAction) {
            AcademicsToolbarSidebarToggleView(
                dispatcher: dispatcher,
                academicsScene: academicsScene
            )
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
