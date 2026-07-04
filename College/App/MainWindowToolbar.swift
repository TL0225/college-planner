// MainWindowToolbar.swift
// Feature: App
// Purpose: Sole activePage router for main window toolbar (ADR 001 → ADR 003 registry).

import SwiftUI

struct MainWindowToolbar: ToolbarContent {
    let activePage: AppPage
    @Binding var academicsInspectorPresented: Bool
    @Binding var documentsSearchText: String
    @Environment(AppContainer.self) private var appContainer

    var body: some ToolbarContent {
        ToolbarProviderRegistry.pageToolbarContent(
            for: activePage,
            context: ToolbarProviderContext(
                store: appContainer.toolbarStore,
                dispatcher: appContainer.toolbarDispatcher,
                calendarScene: appContainer.calendarScene,
                academicsScene: appContainer.academicsScene,
                assistantScene: appContainer.assistantScene,
                collegePersistence: appContainer.persistence,
                activePage: activePage,
                academicsInspectorPresented: $academicsInspectorPresented
            )
        )
    }
}
