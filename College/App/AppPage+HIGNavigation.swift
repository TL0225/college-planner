// AppPage+HIGNavigation.swift
// Feature: App
// Purpose: Maps HIG plan domain objects to College navigation and keyboard shortcuts.

import Foundation

extension AppPage {
    /// HIG plan mapping: Term/Semester → Degree + Academics semesters; Course → Academics;
    /// Assignment → Calendar tasks; Event → Calendar; Note/Resource → Documents (Vault);
    /// Study Session → Calendar study blocks.
    var higDomainLabel: String {
        switch self {
        case .degree: return "Term Overview"
        case .academics: return "Courses"
        case .transferDatabase: return "Transfer Credits"
        case .calendar: return "Events & Tasks"
        case .career: return "Career"
        case .assistant: return "Assistant"
        case .profile: return "Profile"
        case .settings: return "Settings"
        case .lms: return "LMS Portal"
        case .documents: return "Resources"
        case .webShortcut: return "Web Shortcut"
        #if DEBUG
        case .debug: return "Debug"
        #endif
        }
    }

    /// Primary sidebar destinations exposed via View menu and ⌘1–⌘9.
    static let shellSectionShortcuts: [(page: AppPage, keyEquivalent: String)] = [
        (.degree, "1"),
        (.academics, "2"),
        (.transferDatabase, "3"),
        (.calendar, "4"),
        (.career, "5"),
        (.assistant, "6"),
        (.documents, "7"),
        (.profile, "8"),
        (.lms, "9")
    ]

    static func page(forSectionShortcut key: String) -> AppPage? {
        shellSectionShortcuts.first { $0.keyEquivalent == key }?.page
    }
}
