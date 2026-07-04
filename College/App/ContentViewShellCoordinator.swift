// ContentViewShellCoordinator.swift
// Feature: App
// Purpose: Planner/catalog navigation handlers extracted from ContentView (Phase 5 shell).

import SwiftUI

@MainActor
enum ContentViewShellCoordinator {
    static func applyNavigation(
        action: AppNavigationAction,
        setToolbarSearchText: (String) -> Void,
        openPage: (AppPage) -> Void,
        catalogImportCoordinator: CatalogImportCoordinator
    ) {
        switch action {
        case .openPage(let page):
            openPage(page)
        case .openDocuments(let courseCode):
            setToolbarSearchText(courseCode)
            openPage(.documents)
        case .importCatalogBundle(let url):
            catalogImportCoordinator.handleIncomingFile(url: url)
        }
    }
}
