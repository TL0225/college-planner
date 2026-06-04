// AppCompatibility.swift
// Feature: App
// Purpose: App module — PlannerMenuCommands.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

extension AppPage {
    /// Window/menu proxy title when `navigationTitle` is empty (e.g. Settings).
    var windowChromeTitle: String {
        switch self {
        case .documents:
            return String(localized: "documents.screen.title")
        case .assistant:
            return "AI Assistant"
        default:
            return displayTitle
        }
    }

    static func webShortcutPage(id: UUID) -> AppPage { .webShortcut(id: id) }
}

extension Notification.Name {
    static let plannerOpenPage = Notification.Name("plannerOpenPage")
}

enum CollegeInboundURLDispatcher {
    @discardableResult
    static func handle(_ url: URL, spotifyHandler: (URL) -> Void) -> Bool {
        spotifyHandler(url)
        return true
    }
}

struct PlannerMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Assistant") {
            Button("Open AI Assistant") {
                NotificationCenter.default.post(
                    name: .plannerOpenPage,
                    object: nil,
                    userInfo: ["pageRaw": AppPage.assistant.rawValue]
                )
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}
