import EventKit
import Foundation

extension CalendarIntegrationManager {
    public func exportEventToGoogle(_ event: CalendarStoredEvent, targetCalendarID: String? = nil) {
        guard googleStatus == .connected else { return }

        let localIDString = event.id.uuidString
        enqueuePendingUpsert(localID: localIDString)

        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await GoogleCalendarAuthAccess.service!.validAccessToken()
                let success = await self.performExportAsync(
                    localIDString: localIDString,
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.allDay,
                    location: event.location,
                    notes: event.notes,
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

    public func exportEventToAppleCalendar(_ event: CalendarStoredEvent, calendarName: String? = nil) {
        guard appleStatus == .connected else { return }

        let localIDString = event.id.uuidString
        let localUUID = event.id
        let notes = Self.appendCourseTagNotesIfNeeded(event: event)

        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            let targetCalendar: EKCalendar?
            if let name = calendarName,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetCalendar = AppleCalendarIntegration.ensureCalendar(named: name, in: self.eventStore)
            } else {
                targetCalendar = AppleCalendarIntegration.ensurePrimaryCalendar(in: self.eventStore)
            }
            guard let targetCalendar else { return }

            let existingExternal = self.appleExternalID(forLocalID: localIDString)
            let existingEK = existingExternal.flatMap { self.eventStore.event(withIdentifier: $0) }

            let ek: EKEvent = existingEK ?? EKEvent(eventStore: self.eventStore)
            ek.calendar = targetCalendar
            ek.title = event.title
            ek.startDate = event.startDate
            ek.endDate = event.endDate
            ek.isAllDay = event.allDay
            ek.location = event.location
            ek.notes = notes
            ek.url = AppleCalendarIntegration.makeAppEventURL(localID: localUUID)

            do {
                try self.eventStore.save(ek, span: .thisEvent, commit: true)
                if let externalID = AppleCalendarIntegration.bestExternalID(for: ek) {
                    var map = AppleCalendarIntegration.syncMap
                    map[externalID] = localIDString
                    self.setAppleSyncMap(map)
                    CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()
                }
            } catch {
                // Best-effort.
            }
        }
    }

    public func exportEventToOutlook(_ event: CalendarStoredEvent) {
        guard outlookStatus == .connected else { return }
        _ = event
    }

    private static func appendCourseTagNotesIfNeeded(event: CalendarStoredEvent) -> String? {
        let existing = event.notes ?? ""
        guard let courseID = event.courseID?.uuidString, !courseID.isEmpty else {
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
