import EventKit
import Foundation

extension CalendarIntegrationManager {
    public func exportEventToGoogle(_ event: CalendarStoredEvent, targetCalendarID: String? = nil) {
        Task { await exportEventToGoogleAsync(event, targetCalendarID: targetCalendarID) }
    }

    func exportEventToGoogleAsync(
        _ event: CalendarStoredEvent,
        targetCalendarID: String? = nil
    ) async -> Bool {
        guard googleStatus == .connected else { return false }

        let localIDString = event.id.uuidString
        if let inFlight = googleExportInFlight[localIDString] {
            return await inFlight.value
        }

        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            enqueuePendingUpsert(localID: localIDString)
            do {
                let token = try await GoogleCalendarAuthAccess.service!.validAccessToken()
                let notes = Self.appendCourseTagNotesIfNeeded(event: event)
                let success = await self.performExportAsync(
                    localIDString: localIDString,
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.allDay,
                    location: event.location,
                    notes: notes,
                    recurrenceRule: event.recurrenceRule,
                    attendeesJSON: event.attendeesJSON,
                    token: token,
                    overrideCalendarID: targetCalendarID
                )
                if success {
                    removePendingUpsert(localID: localIDString)
                }
                return success
            } catch {
                #if DEBUG
                    print("[Calendar][Google] Skipping export (no token): \(error.localizedDescription)")
                #endif
                return false
            }
        }

        googleExportInFlight[localIDString] = task
        let result = await task.value
        googleExportInFlight[localIDString] = nil
        return result
    }

    public func exportEventToAppleCalendar(_ event: CalendarStoredEvent, calendarName: String? = nil) {
        Task { await exportEventToAppleCalendarAsync(event, calendarName: calendarName) }
    }

    func exportEventToAppleCalendarAsync(
        _ event: CalendarStoredEvent,
        calendarName: String? = nil
    ) async -> Bool {
        guard appleStatus == .connected else { return false }

        let localIDString = event.id.uuidString
        let localUUID = event.id
        let notes = Self.appendCourseTagNotesIfNeeded(event: event)

        let targetCalendar: EKCalendar?
        if let name = calendarName,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            targetCalendar = AppleCalendarIntegration.ensureCalendar(named: name, in: eventStore)
        } else {
            targetCalendar = AppleCalendarIntegration.ensurePrimaryCalendar(in: eventStore)
        }
        guard let targetCalendar else { return false }

        let existingExternal = appleExternalID(forLocalID: localIDString)
        let existingEK = existingExternal.flatMap { eventStore.event(withIdentifier: $0) }

        let ek: EKEvent = existingEK ?? EKEvent(eventStore: eventStore)
        ek.calendar = targetCalendar
        ek.title = event.title
        ek.startDate = event.startDate
        ek.endDate = event.endDate
        ek.isAllDay = event.allDay
        ek.location = event.location
        ek.notes = CalendarGuestInviteExporter.appleNotesWithGuestRoster(
            notes: notes,
            attendeesJSON: event.attendeesJSON
        )
        ek.url = AppleCalendarIntegration.makeAppEventURL(localID: localUUID)
        ek.recurrenceRules = CalendarRecurrenceRuleCodec.ekRecurrenceRules(from: event.recurrenceRule)

        do {
            try eventStore.save(ek, span: .thisEvent, commit: true)
            if let externalID = AppleCalendarIntegration.bestExternalID(for: ek) {
                var map = AppleCalendarIntegration.syncMap
                map[externalID] = localIDString
                setAppleSyncMap(map)
                CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()
            }
            return true
        } catch {
            return false
        }
    }

    public func exportEventToOutlook(_ event: CalendarStoredEvent) {
        guard outlookStatus == .connected else { return }
        Task { await exportEventToOutlookAsync(event) }
    }

    func exportEventToOutlookAsync(_ event: CalendarStoredEvent) async -> Bool {
        guard outlookStatus == .connected else { return false }
        do {
            let token = try await OutlookAuthService.shared.validAccessToken()
            return await performOutlookExportAsync(event: event, token: token)
        } catch {
            #if DEBUG
                print("[Calendar][Outlook] Skipping export (no token): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func exportEventToiCloudAsync(_ event: CalendarStoredEvent) async -> Bool {
        guard iCloudStatus == .connected else { return false }
        guard let username = iCloudKeychainGet(iCloudUsernameKey),
              let password = iCloudKeychainGet(iCloudPasswordKey)
        else { return false }
        return await performiCloudExportAsync(event: event, username: username, password: password)
    }

    static func appendCourseTagNotesIfNeeded(event: CalendarStoredEvent) -> String? {
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
