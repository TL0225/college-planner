// ToolbarProviderRegistry.swift
// Feature: App / Toolbar
// Purpose: ADR 003 — page → toolbar provider registry (delegates from MainWindowToolbar).

import SwiftUI

@MainActor
enum ToolbarProviderRegistry {
    @ToolbarContentBuilder
    static func pageToolbarContent(
        for page: AppPage,
        context: ToolbarProviderContext
    ) -> some ToolbarContent {
        switch page.routingFamily {
        case .web:
            WebToolbarProvider.toolbarContent(context: context)
        case .empty:
            ToolbarContentEmpty()
        case .feature(let featurePage):
            featureToolbar(for: featurePage, context: context)
        }
    }

    @ToolbarContentBuilder
    private static func featureToolbar(
        for page: AppPage.FeatureToolbarPage,
        context: ToolbarProviderContext
    ) -> some ToolbarContent {
        switch page {
        case .calendar:
            CalendarToolbarProvider.toolbarContent(context: context)
        case .academics:
            AcademicsToolbarProvider.toolbarContent(context: context)
        case .transferDatabase:
            TransferToolbarProvider.toolbarContent(context: context)
        case .career:
            CareerToolbarProvider.toolbarContent(context: context)
        case .assistant:
            AssistantToolbarProvider.toolbarContent(context: context)
        case .profile:
            ProfileToolbarProvider.toolbarContent(context: context)
        }
    }
}

private enum ToolbarRoutingFamily {
    case web
    case empty
    case feature(AppPage.FeatureToolbarPage)
}

private extension AppPage {
    enum FeatureToolbarPage {
        case calendar
        case academics
        case transferDatabase
        case career
        case assistant
        case profile
    }

    var routingFamily: ToolbarRoutingFamily {
        switch self {
        case .calendar: return .feature(.calendar)
        case .academics: return .feature(.academics)
        case .transferDatabase: return .feature(.transferDatabase)
        case .career: return .feature(.career)
        case .assistant: return .feature(.assistant)
        case .profile: return .feature(.profile)
        case .webShortcut, .lms: return .web
        case .degree, .documents, .settings: return .empty
        #if DEBUG
        case .debug: return .empty
        #endif
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
