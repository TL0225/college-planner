// ToolbarProviderRegistry.swift
// Feature: App / Toolbar
// Purpose: ADR 003 — page → toolbar content registry (delegates from MainWindowToolbar).

import SwiftUI

enum ToolbarProviderRegistry {
    @ToolbarContentBuilder
    static func pageToolbarContent(
        for page: AppPage,
        academicsInspectorPresented: Binding<Bool>
    ) -> some ToolbarContent {
        switch page {
        case .calendar:
            CalendarToolbarContent()
        case .academics:
            AcademicsToolbarContent(academicsInspectorPresented: academicsInspectorPresented)
        case .career:
            CareerToolbarContent(activePage: page)
        case .webShortcut:
            WebToolbarContent()
        default:
            ToolbarContentEmpty()
        }
    }
}

/// Placeholder for pages without dedicated toolbar chrome (satisfies ToolbarContentBuilder).
private struct ToolbarContentEmpty: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }
}
