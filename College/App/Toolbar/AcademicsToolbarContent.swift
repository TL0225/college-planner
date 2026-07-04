// AcademicsToolbarContent.swift
// Feature: App / Toolbar

import CollegeAcademics
import SwiftUI

struct AcademicsToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher
    let academicsScene: AcademicsSceneState
    let collegePersistence: CollegePersistence

    var body: some ToolbarContent {
        ToolbarItem(id: "academics.degreeScope", placement: .principal) {
            AcademicsDegreeScopeToolbar(
                collegePersistence: collegePersistence,
                academicsScene: academicsScene
            )
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "academics.addCourse", placement: .primaryAction) {
            Button {
                dispatcher.dispatch(.academics(.addCourse))
            } label: {
                Label("Add Course", systemImage: "plus")
            }
            .help("Add a course from the catalog")
            .accessibilityIdentifier("toolbar.academics.addCourse")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
