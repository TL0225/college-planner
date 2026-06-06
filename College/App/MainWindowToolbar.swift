// MainWindowToolbar.swift
// Feature: App
// Purpose: Sole activePage router for main window toolbar (ADR 001 → ADR 003 registry).

import SwiftUI

struct MainWindowToolbar: ToolbarContent {
    let activePage: AppPage
    @Binding var academicsInspectorPresented: Bool

    var body: some ToolbarContent {
        DefaultToolbarItem(kind: .sidebarToggle, placement: .automatic)
        ToolbarProviderRegistry.pageToolbarContent(
            for: activePage,
            academicsInspectorPresented: $academicsInspectorPresented
        )
    }
}
