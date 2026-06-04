// CalendarIntegrationManager+StoreExport.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarIntegrationManager+StoreExport.
// Data: CollegePersistence / repositories when applicable.

import EventKit
import Foundation
import SwiftData

extension CalendarIntegrationManager {
    func exportEventToGoogle(_ event: CalendarEvent, targetCalendarID: String? = nil) {
        guard googleStatus == .connected else { return }

        let localIDString = event.id.uuidString
        let title = event.title
        let notes = event.notes
        let location = event.location
        let start = event.startDate
        let end = event.endDate
        let isAllDay = event.allDay

        enqueuePendingUpsert(localID: localIDString)

        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await GoogleAuthService.shared.validAccessToken()
                let success = await self.performExportAsync(
                    localIDString: localIDString,
                    title: title,
                    start: start,
                    end: end,
                    isAllDay: isAllDay,
                    location: location,
                    notes: notes,
                    token: token,
                    overrideCalendarID: targetCalendarID
                )
                if success {
                    await MainActor.run { self.removePendingUpsert(localID: localIDString) }
                }
            } catch {
                #if DEBUG
                    print("[Calendar][Google] Skipping export (no token): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func exportEventToAppleCalendar(_ event: CalendarEvent, calendarName: String? = nil) {
        guard appleStatus == .connected else { return }

        let localIDString = event.id.uuidString
        let localUUID = event.id
        let title = event.title
        let notes = Self.appendCourseTagNotesIfNeeded(swiftEvent: event)
        let location = event.location
        let start = event.startDate
        let end = event.endDate
        let isAllDay = event.allDay

        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            let targetCalendar: EKCalendar?
            if let name = calendarName,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetCalendar = AppleCalendarIntegration.ensureCalendar(
                    named: name, in: self.eventStore)
            } else {
                targetCalendar = AppleCalendarIntegration.ensurePrimaryCalendar(in: self.eventStore)
            }
            guard let targetCalendar else { return }

            let existingExternal = self.appleExternalID(forLocalID: localIDString)
            let existingEK = existingExternal.flatMap { self.eventStore.event(withIdentifier: $0) }

            let ek: EKEvent = existingEK ?? EKEvent(eventStore: self.eventStore)
            ek.calendar = targetCalendar
            ek.title = title
            ek.startDate = start
            ek.endDate = end
            ek.isAllDay = isAllDay
            ek.location = location
            ek.notes = notes
            ek.url = AppleCalendarIntegration.makeAppEventURL(localID: localUUID)

            do {
                try self.eventStore.save(ek, span: .thisEvent, commit: true)
                if let externalID = AppleCalendarIntegration.bestExternalID(for: ek) {
                    var map = AppleCalendarIntegration.syncMap
                    map[externalID] = localIDString
                    self.setAppleSyncMap(map)
                    CollegePersistence.shared.notifyCalendarDidChange()
                }
            } catch {
                // Best-effort.
            }
        }
    }

    func exportEventToOutlook(_ event: CalendarEvent) {
        guard outlookStatus == .connected else { return }
        _ = event
        // Outlook export is handled during the next scheduled sync.
    }

    private static func appendCourseTagNotesIfNeeded(swiftEvent event: CalendarEvent) -> String? {
        let existing = event.notes ?? ""
        guard let courseID = event.course?.id.uuidString, !courseID.isEmpty else {
            return existing.isEmpty ? nil : existing
        }
        let tag = "[course_uuid]=\(courseID)"
        if existing.contains(tag) {
            return existing.isEmpty ? nil : existing
        }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tag
        }
        return existing + "\n\n" + tag
    }
}
