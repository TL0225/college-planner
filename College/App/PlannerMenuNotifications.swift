// PlannerMenuNotifications.swift
// Feature: App
// Purpose: App module — MacPreferencesWindow.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

extension Notification.Name {
    /// Triggers the same portal backup export flow as the main-window toolbar.
    static let plannerExportPortalBackup = Notification.Name("com.timothy.college.plannerExportPortalBackup")
    /// Opens the encrypted backup import panel from the menu bar.
    static let plannerImportPortalBackupMenu = Notification.Name("com.timothy.college.plannerImportPortalBackupMenu")
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
    @MainActor
    static func show() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
