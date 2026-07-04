// ToolbarProviding.swift
// Feature: App / Toolbar
// Purpose: ADR 003 — per-feature toolbar provider protocol and routing context.

import CollegeAcademics
import CollegeCalendar
import SwiftUI

/// Window-scoped inputs passed from `MainWindowToolbar` into feature providers.
struct ToolbarProviderContext {
    let store: AppToolbarStore
    let dispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState
    let academicsScene: AcademicsSceneState
    let assistantScene: AssistantSceneState
    let collegePersistence: CollegePersistence
    let activePage: AppPage
    var academicsInspectorPresented: Binding<Bool>
}

/// Each major page registers a provider; the registry stays O(features) instead of O(pages).
@MainActor
protocol ToolbarProviding {
    associatedtype Content: ToolbarContent

    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> Content
}

enum CalendarToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        CalendarToolbarContent(
            dispatcher: context.dispatcher,
            calendarScene: context.calendarScene
        )
    }
}

enum AcademicsToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        AcademicsToolbarContent(
            dispatcher: context.dispatcher,
            academicsScene: context.academicsScene,
            collegePersistence: context.collegePersistence
        )
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

enum TransferToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        TransferToolbarContent(dispatcher: context.dispatcher)
    }
}

/// Minimal Transfer Database toolbar: refresh official sources, import community data, toggle mode.
struct TransferToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                dispatcher.dispatch(.transfer(.refreshOfficial))
            } label: {
                Label("Refresh Sources", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("toolbar.transfer.refresh")
            Button {
                dispatcher.dispatch(.transfer(.importCommunity))
            } label: {
                Label("Import Community Data", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("toolbar.transfer.import")
            Button {
                dispatcher.dispatch(.transfer(.addManualEntry))
            } label: {
                Label("Add Manual Entry", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("toolbar.transfer.addManual")
            Button {
                dispatcher.dispatch(.transfer(.shareToCommunity))
            } label: {
                Label("Share to Community", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("toolbar.transfer.share")
            Button {
                dispatcher.dispatch(.transfer(.toggleMode))
            } label: {
                Label("Toggle Source Mode", systemImage: "switch.2")
            }
            .accessibilityIdentifier("toolbar.transfer.toggleMode")
        }
    }
}
