// AcademicCalendarImportPromptBridge.swift
// Feature: Calendar
// Purpose: Schedule a post-catalog prompt to import university term dates.

import Foundation

enum AcademicCalendarImportPromptBridge {
    static let pendingImportKey = "calendar.pendingTermDatesImport.v1"

    @MainActor
    static func schedulePromptIfAppropriate(persistence: CollegePersistence) {
        guard AcademicCalendarImportCoordinator.canOfferImport(persistence: persistence) else { return }
        guard !UserDefaults.standard.bool(forKey: pendingImportKey) else { return }
        UserDefaults.standard.set(true, forKey: pendingImportKey)
        NotificationCenter.default.post(name: .academicCalendarImportPromptScheduled, object: nil)
    }

    static var isPending: Bool {
        UserDefaults.standard.bool(forKey: pendingImportKey)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingImportKey)
    }
}

extension Notification.Name {
    static let academicCalendarImportPromptScheduled = Notification.Name("academicCalendarImportPromptScheduled")
}
