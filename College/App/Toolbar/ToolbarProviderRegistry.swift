// ToolbarProviderRegistry.swift
// Feature: App / Toolbar
// Purpose: ADR 003 — page → toolbar provider registry (delegates from MainWindowToolbar).

import SwiftUI

enum ToolbarProviderRegistry {
    @ToolbarContentBuilder
    static func pageToolbarContent(
        for page: AppPage,
        context: ToolbarProviderContext
    ) -> some ToolbarContent {
        switch page {
        case .calendar:
            CalendarToolbarProvider.toolbarContent(context: context)
        case .academics:
            AcademicsToolbarProvider.toolbarContent(context: context)
        case .career:
            CareerToolbarProvider.toolbarContent(context: context)
        case .webShortcut:
            WebToolbarProvider.toolbarContent(context: context)
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
