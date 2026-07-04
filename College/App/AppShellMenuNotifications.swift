// AppShellMenuNotifications.swift
// Feature: App
// Purpose: Menu-bar commands for shell chrome (sidebar, inspector, search focus).

import Foundation

extension Notification.Name {
    /// Toggles the inspector for the active page (Documents, Career, Academics stats column).
    static let collegeToggleInspector = Notification.Name("college.toggleInspector")
    /// Focuses the active page search field (⌘F).
    static let collegeFocusSearch = Notification.Name("college.focusSearch")
    /// Opens Privacy Overview sheet (Help menu).
    static let collegeShowPrivacyOverview = Notification.Name("college.showPrivacyOverview")
    /// Opens Diagnostics center sheet (Help menu, DEBUG builds).
    static let collegeShowDiagnostics = Notification.Name("college.showDiagnostics")
    /// Toggles Career subview inspectors (board job, openings detail, networking selection).
    static let collegeCareerToggleInspector = Notification.Name("college.careerToggleInspector")
    /// Opens the first available Career inspector row when none is selected.
    static let collegeCareerOpenInspectorSelection = Notification.Name("college.careerOpenInspectorSelection")
    /// Opens a tear-off Documents window (Window > New Documents Window).
    static let collegeOpenDocumentsWindow = Notification.Name("college.openDocumentsWindow")
    /// Selects a Career subview from the View menu (`userInfo["rawValue"]` as `String`).
    static let careerSelectSubview = Notification.Name("college.careerSelectSubview")
    /// Selects a Calendar inspector panel (`userInfo["panel"]` as `String` raw value).
    static let collegeCalendarSelectSidebarPanel = Notification.Name("college.calendarSelectSidebarPanel")
    /// Opens the Academics Add Course flow from the View menu.
    static let collegeAcademicsAddCourse = Notification.Name("college.academicsAddCourse")
    /// Assistant menu → toolbar parity hooks.
    static let collegeAssistantOpenWebMemory = Notification.Name("college.assistant.openWebMemory")
    static let collegeAssistantExportTranscript = Notification.Name("college.assistant.exportTranscript")
    static let collegeAssistantClearThread = Notification.Name("college.assistant.clearThread")
    static let collegeProfileEditProfile = Notification.Name("college.profile.editProfile")
    static let collegeCareerAddApplication = Notification.Name("college.career.addApplication")
    /// Opens the Transfer community JSON importer (File menu).
    static let transferImportCommunityJSON = Notification.Name("college.transferImportCommunityJSON")
}
