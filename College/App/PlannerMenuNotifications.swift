// PlannerMenuNotifications.swift
// Feature: App
// Purpose: App module — MacPreferencesWindow.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

extension Notification.Name {
    /// Import a `.portal` file passed from Finder or `NSApplicationDelegate` (`userInfo["url"]` as `URL`).
    static let plannerImportPortalBackupFileURL = Notification.Name("com.timothy.college.plannerImportPortalBackupFileURL")
    /// Fired by the Profile toolbar button to open the Advisor Meeting Prep sheet.
    static let profileOpenAdvisorPrep = Notification.Name("com.timothy.college.profileOpenAdvisorPrep")
    /// Opens Documents and pre-fills the search query using a normalized course code (`userInfo["courseCode"]`).
    static let plannerOpenDocumentsForCourse = Notification.Name("com.timothy.college.plannerOpenDocumentsForCourse")
    /// Import a `.collegecatalog` file (`userInfo["url"]` as `URL`).
    static let plannerImportCatalogBundleFileURL = Notification.Name("com.timothy.college.plannerImportCatalogBundleFileURL")
}

enum MacPreferencesWindow {
    static func show(section: SettingsNavSection? = nil) {
        DispatchQueue.main.async {
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                postSection(section)
                return
            }
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            postSection(section)
        }
    }

    private static func postSection(_ section: SettingsNavSection?) {
        guard let section else { return }
        NotificationCenter.default.post(
            name: .plannerOpenSettingsSection,
            object: nil,
            userInfo: ["sectionRaw": section.rawValue]
        )
    }
}
