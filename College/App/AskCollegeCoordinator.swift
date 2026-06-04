// AskCollegeCoordinator.swift
// Feature: App
// Purpose: App module — AskCollegeCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import AppKit

/// Global Ask College sheet presentation (menu ⌘⇧K).
enum AskCollegeCoordinator {
    @MainActor
    static func present(from activePage: AppPage) {
        NotificationCenter.default.post(
            name: .askCollegePresent,
            object: nil,
            userInfo: ["restorePageRaw": activePage.rawValue]
        )
    }

    @MainActor
    static func navigateToPage(_ page: AppPage) -> Bool {
        NotificationCenter.default.post(
            name: .plannerOpenPage,
            object: nil,
            userInfo: ["pageRaw": page.rawValue]
        )
        return true
    }

    @MainActor
    static func openSettingsSection(_ section: SettingsNavSection) -> Bool {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(
            name: .plannerOpenSettingsSection,
            object: nil,
            userInfo: ["sectionRaw": section.rawValue]
        )
        return true
    }
}

extension Notification.Name {
    static let askCollegePresent = Notification.Name("askCollegePresent")
    static let plannerOpenSettingsSection = Notification.Name("plannerOpenSettingsSection")
}
