// AcademicCalendarIntegration.swift
// Feature: Calendar
// Purpose: Bridge academic calendar configs with CalendarIntegrationManager sidebar.

import CollegeCalendar
import Foundation

extension Notification.Name {
  static let academicCalendarConfigsDidChange = Notification.Name("academicCalendarConfigsDidChange")
}

@MainActor
enum AcademicCalendarIntegration {
  private static var isSyncingRegistrations = false

  static func notifyConfigsDidChange() {
    NotificationCenter.default.post(name: .academicCalendarConfigsDidChange, object: nil)
  }

  static func registerCalendarIfNeeded(config: AcademicCalendarConfig, calendarManager: CalendarIntegrationManager) {
    calendarManager.registerAcademicDepartmentCalendar(
      schoolID: config.schoolID,
      schoolDisplayName: config.schoolDisplayName,
      departmentKey: config.departmentKey,
      departmentDisplayName: config.departmentDisplayName
    )
  }

  static func syncAllRegistrations(calendarManager: CalendarIntegrationManager) {
    guard !isSyncingRegistrations else { return }
    isSyncingRegistrations = true
    defer { isSyncingRegistrations = false }

    AcademicCalendarStore.runMigrationIfNeeded(calendarManager: calendarManager)
    for config in AcademicCalendarStore.loadAllConfigs() {
      registerCalendarIfNeeded(config: config, calendarManager: calendarManager)
    }
  }

  static func removeCalendar(configID: String, calendarManager: CalendarIntegrationManager) {
    guard let config = AcademicCalendarStore.config(configID: configID) else { return }
    let provider = config.providerSource
    let repo = AppDataStore.shared.calendarRepository
    let events = (try? repo.fetchEventsOverlapping(start: .distantPast, end: .distantFuture, limit: 5000)) ?? []
    for event in events where event.providerSource == provider {
      try? repo.deleteCalendarEvent(id: event.id)
    }
    AcademicCalendarStore.removeConfig(configID: configID)
    calendarManager.removeAcademicDepartmentCalendar(schoolID: config.schoolID, departmentKey: config.departmentKey)
    CollegePersistence.shared.notifyCalendarDidChange()
    notifyConfigsDidChange()
  }

  static func removeCalendar(schoolID: String, calendarManager: CalendarIntegrationManager) {
    for config in AcademicCalendarStore.configs(for: schoolID) {
      removeCalendar(configID: config.configID, calendarManager: calendarManager)
    }
  }
}
