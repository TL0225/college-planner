// ToolbarProviding.swift
// Feature: App / Toolbar
// Purpose: ADR 003 — per-feature toolbar provider protocol and routing context.

import SwiftUI

/// Window-scoped inputs passed from `MainWindowToolbar` into feature providers.
struct ToolbarProviderContext {
    let store: AppToolbarStore
    let dispatcher: ToolbarDispatcher
    let activePage: AppPage
    var academicsInspectorPresented: Binding<Bool>
}

/// Each major page registers a provider; the registry stays O(features) instead of O(pages).
protocol ToolbarProviding {
    associatedtype Content: ToolbarContent

    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> Content
}

enum CalendarToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        CalendarToolbarContent()
    }
}

enum AcademicsToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        AcademicsToolbarContent(academicsInspectorPresented: context.academicsInspectorPresented)
    }
}

enum CareerToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        CareerToolbarContent(activePage: context.activePage)
    }
}

enum WebToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        WebToolbarContent()
    }
}
