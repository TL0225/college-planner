// AppPageToolbarMetadata.swift
// Feature: App / Toolbar
// Purpose: Static registry for architecture tests — every AppPage maps to toolbar content.

import Foundation
import SwiftUI

enum AppPageToolbarMetadata {
    struct Entry: Sendable {
        let toolbarContentTypeName: String
        let toolbarProviderTypeName: String
        let hasDedicatedToolbarChrome: Bool
    }

    static func entry(for page: AppPage) -> Entry {
        switch page {
        case .calendar:
            return Entry(
                toolbarContentTypeName: "CalendarToolbarContent",
                toolbarProviderTypeName: "CalendarToolbarProvider",
                hasDedicatedToolbarChrome: true
            )
        case .academics:
            return Entry(
                toolbarContentTypeName: "AcademicsToolbarContent",
                toolbarProviderTypeName: "AcademicsToolbarProvider",
                hasDedicatedToolbarChrome: true
            )
        case .career:
            return Entry(
                toolbarContentTypeName: "CareerToolbarContent",
                toolbarProviderTypeName: "CareerToolbarProvider",
                hasDedicatedToolbarChrome: true
            )
        case .webShortcut:
            return Entry(
                toolbarContentTypeName: "WebToolbarContent",
                toolbarProviderTypeName: "WebToolbarProvider",
                hasDedicatedToolbarChrome: true
            )
        case .brightspace:
            return Entry(
                toolbarContentTypeName: "None",
                toolbarProviderTypeName: "None",
                hasDedicatedToolbarChrome: false
            )
        case .degree, .assistant, .profile, .settings, .documents:
            return Entry(
                toolbarContentTypeName: "None",
                toolbarProviderTypeName: "None",
                hasDedicatedToolbarChrome: false
            )
        #if DEBUG
        case .debug:
            return Entry(
                toolbarContentTypeName: "None",
                toolbarProviderTypeName: "None",
                hasDedicatedToolbarChrome: false
            )
        #endif
        }
    }

    static var allPages: [AppPage] {
        var pages: [AppPage] = [
            .degree, .academics, .calendar, .career, .assistant, .profile,
            .settings, .brightspace, .documents,
            .webShortcut(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        ]
        #if DEBUG
        pages.append(.debug)
        #endif
        return pages
    }
}
