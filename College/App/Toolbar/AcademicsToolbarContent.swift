// AcademicsToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct AcademicsToolbarContent: ToolbarContent {
    @Binding var academicsInspectorPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(id: "academics.degreeScope", placement: .principal) {
            HStack(spacing: 8) {
                AcademicsDegreeScopeToolbar()
                AcademicsToolbarAddProfileButton()
            }
        }
        ToolbarItem(id: "academics.sidebarToggle", placement: .primaryAction) {
            AcademicsToolbarSidebarToggleView()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
