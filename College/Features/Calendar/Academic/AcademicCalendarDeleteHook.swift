// AcademicCalendarDeleteHook.swift
// Feature: Calendar
// Purpose: Record per-event deletions for academic calendar imports.

import Foundation

@MainActor
enum AcademicCalendarDeleteHook {
  static func recordDeletionIfNeeded(eventID: UUID) {
    guard let event = try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: eventID),
          let source = event.providerSource,
          let parsed = AcademicCalendarConfig.parseProviderSource(source) else { return }

    let configID = AcademicCalendarConfig.makeConfigID(
      schoolID: parsed.schoolID,
      departmentKey: parsed.departmentKey
    )
    let ledger = AcademicCalendarStore.loadLedger(configID: configID)
    if let entry = ledger.first(where: { $0.localID == eventID }) {
      AcademicCalendarStore.appendDeletedKey(configID: configID, identityKey: entry.identityKey)
    } else if let providerEventId = event.providerEventId, !providerEventId.isEmpty {
      AcademicCalendarStore.appendDeletedKey(
        configID: configID,
        identityKey: AcademicCalendarIdentityResolver.icsIdentityKey(uid: providerEventId)
      )
    }
  }
}
