import Foundation
import os

private enum GoogleSyncDateParsing {
    nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) static let ymdFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()

    static func parseISO8601(_ value: String) -> Date? {
        isoFormatter.date(from: value)
    }

    static func parseYMD(_ value: String) -> Date? {
        ymdFormatter.date(from: value)
    }
}

extension CalendarIntegrationManager {
    private static let googleRemoteKeySeparatorForSync = "||"

    private func googleRemoteKeyForSync(calendarID: String, eventID: String) -> String {
        "\(calendarID)\(Self.googleRemoteKeySeparatorForSync)\(eventID)"
    }

    func purgeGoogleCalendarEventsFromStoreAndClearState() {
        let localIDs = syncMap.values.compactMap { UUID(uuidString: $0) }

        #if DEBUG
            debugLog(
                "disconnectGoogle(): purging \(localIDs.count) local events belonging to Google calendar"
            )
        #endif

        setSyncMap([:])
        deletedIDs = []
        pendingDeletionIDs = []
        pendingUpsertLocalIDs = []

        guard !localIDs.isEmpty else {
            notifyCalendarDidChangeMainActor()
            return
        }

        CalendarPersistenceAccess.persistence?.bulkDeleteCalendarEvents(withUUIDs: localIDs)

        #if DEBUG
            debugLog("disconnectGoogle(): purge complete (deleted=\(localIDs.count))")
        #endif
        notifyCalendarDidChangeMainActor()
    }

    func syncGoogleEventsToStore(
        _ items: [GoogleCalendarEventItem],
        calendarID: String,
        syncNotificationID: UUID? = nil,
        completion: @Sendable @escaping () -> Void
    ) {
        #if DEBUG
            let log = Self.perfLog
            let spid = OSSignpostID(log: log)
            os_signpost(
                .begin,
                log: log,
                name: "Googlelocal storeSync",
                signpostID: spid,
                "calendar=%{public}@",
                calendarID
            )
        #endif

        let currentMap = syncMap
        let mappedLocalIDsLower = Set(currentMap.values.map { $0.lowercased() })
        let deletedTombstones = Set(deletedIDs)
        let snapshots = buildGoogleEventSnapshots(items: items, calendarID: calendarID)

        Task { @MainActor [weak self] in
            guard let self else {
                #if DEBUG
                    os_signpost(.end, log: log, name: "Googlelocal storeSync", signpostID: spid)
                #endif
                completion()
                return
            }

            guard let ingest = CalendarIntegrationAccess.syncIngest else {
                completion()
                return
            }

            let result: CalendarGoogleIngestResult
            do {
                result = try ingest.ingestGoogleSnapshots(
                    snapshots: snapshots,
                    calendarID: calendarID,
                    currentMap: currentMap,
                    mappedLocalIDsLower: mappedLocalIDsLower,
                    deletedTombstones: deletedTombstones
                )
            } catch {
                #if DEBUG
                    self.debugLog("syncGoogleEventsToStore: ingest FAILED: \(error)")
                    os_signpost(.end, log: log, name: "Googlelocal storeSync", signpostID: spid)
                #endif
                completion()
                return
            }

            var map = self.syncMap
            for key in result.mapRemovals {
                map.removeValue(forKey: key)
            }
            for (k, v) in result.mapUpdates {
                map[k] = v
            }
            self.setSyncMap(map)

            if !result.cancelledRemoteKeys.isEmpty {
                var existing = Set(self.deletedIDs)
                for key in result.cancelledRemoteKeys { existing.insert(key) }
                self.deletedIDs = Array(existing)
            }

            #if DEBUG
                self.debugLog("Synced \(result.newCount) new events to local store.")
                os_signpost(.end, log: log, name: "Googlelocal storeSync", signpostID: spid)
            #endif

            if let syncNotificationID {
                if result.newCount > 0 {
                    CalendarNotificationAccess.notifications?.complete(
                        id: syncNotificationID,
                        kind: .success,
                        title: "Calendar Synced",
                        message:
                            "\(result.newCount) new event\(result.newCount == 1 ? "" : "s") synced from Google Calendar",
                        autoDismissAfter: 4
                    )
                } else {
                    CalendarNotificationAccess.notifications?.complete(
                        id: syncNotificationID,
                        kind: .success,
                        title: "Calendar Synced",
                        message: "Calendar is up to date",
                        autoDismissAfter: 4
                    )
                }
            }

            self.notifyCalendarDidChangeMainActor()
            completion()
        }
    }

    private func buildGoogleEventSnapshots(
        items: [GoogleCalendarEventItem],
        calendarID: String
    ) -> [CalendarGoogleIngestSnapshot] {
        items.compactMap { item in
            let remoteKey = googleRemoteKeyForSync(calendarID: calendarID, eventID: item.id)
            let legacyKey = item.id

            if item.status == "cancelled" {
                return CalendarGoogleIngestSnapshot(
                    remoteKey: remoteKey,
                    legacyKey: legacyKey,
                    providerEventId: item.id,
                    title: item.summary ?? "(No Title)",
                    start: .distantPast,
                    end: .distantPast,
                    isAllDay: false,
                    location: nil,
                    notes: nil,
                    status: item.status,
                    customColorHex: nil,
                    recurrenceRule: nil,
                    attendeesJSON: nil,
                    isCancelled: true
                )
            }

            var startDate: Date?
            var endDate: Date?
            var isAllDay = false

            if let dt = item.start.dateTime {
                startDate = GoogleSyncDateParsing.parseISO8601(dt)
            } else if let d = item.start.date {
                startDate = GoogleSyncDateParsing.parseYMD(d)
                isAllDay = true
            }

            if let dt = item.end.dateTime {
                endDate = GoogleSyncDateParsing.parseISO8601(dt)
            } else if let d = item.end.date {
                endDate = GoogleSyncDateParsing.parseYMD(d)
            }

            guard let finalStart = startDate, let finalEnd = endDate else { return nil }

            let baseNotes = item.description
            let conferenceURL = GoogleAttendeeHelper.primaryJoinURL(from: item.conferenceData)
            let notes = CalendarSyncIngestNotes.appendingConferenceURL(
                notes: baseNotes,
                conferenceURL: conferenceURL
            )
            let recurrenceRule = GoogleAttendeeHelper.rrule(from: item.recurrence)
            let attendeesJSON = GoogleAttendeeHelper.encode(item.attendees ?? [])

            return CalendarGoogleIngestSnapshot(
                remoteKey: remoteKey,
                legacyKey: legacyKey,
                providerEventId: item.id,
                title: item.summary ?? "(No Title)",
                start: finalStart,
                end: finalEnd,
                isAllDay: isAllDay,
                location: item.location,
                notes: notes,
                status: item.status,
                customColorHex: item.colorId,
                recurrenceRule: recurrenceRule,
                attendeesJSON: attendeesJSON,
                isCancelled: false
            )
        }
    }

    func fetchLocalEvent(uuid: UUID) -> CalendarStoredEvent? {
        try? CalendarPersistenceAccess.writeRepository?.fetchCalendarEvent(id: uuid)
    }

    func fetchLocalEventsBatch(uuids: [UUID]) -> [UUID: CalendarStoredEvent] {
        guard !uuids.isEmpty else { return [:] }
        var result: [UUID: CalendarStoredEvent] = [:]
        result.reserveCapacity(uuids.count)
        for uuid in uuids {
            if let event = try? CalendarPersistenceAccess.writeRepository?.fetchCalendarEvent(id: uuid) {
                result[uuid] = event
            }
        }
        return result
    }

    func syncOutlookEventsToStore(
        _ items: [[String: Any]], calendarID: String, syncNotificationID: UUID?
    ) async {
        let currentMap = outlookSyncMap
        let fmt1 = OutlookImportDateFormatters.fmt1
        let fmt2 = OutlookImportDateFormatters.fmt2
        let fmtD = OutlookImportDateFormatters.fmtD

        func parseDate(_ d: [String: Any]?, tz: TimeZone) -> Date? {
            guard let str = d?["dateTime"] as? String else { return nil }
            fmt1.timeZone = tz
            fmt2.timeZone = tz
            return fmt1.date(from: str) ?? fmt2.date(from: str)
                ?? fmtD.date(from: String(str.prefix(10)))
        }

        let snapshots: [CalendarOutlookIngestSnapshot] = items.compactMap { item in
            guard let remoteID = item["id"] as? String else { return nil }
            let title = item["subject"] as? String ?? "(No Title)"
            let isAllDay = item["isAllDay"] as? Bool ?? false
            let loc = (item["location"] as? [String: Any])?["displayName"] as? String
            let body = (item["body"] as? [String: Any])?["content"] as? String
            let bodyPreview = item["bodyPreview"] as? String
            let conferenceURL =
                ((item["onlineMeeting"] as? [String: Any])?["joinUrl"] as? String)
                ?? (item["onlineMeetingUrl"] as? String)
                ?? (item["webLink"] as? String)
            let sDict = item["start"] as? [String: Any]
            let eDict = item["end"] as? [String: Any]
            let tzIDVal = sDict?["timeZone"] as? String
            let tz = TimeZone(identifier: tzIDVal ?? "UTC") ?? TimeZone(identifier: "UTC")!
            guard let start = parseDate(sDict, tz: tz), let end = parseDate(eDict, tz: tz) else {
                return nil
            }
            let markdownDescription = bodyPreview?.isEmpty == false ? bodyPreview : body
            let notes = CalendarSyncIngestNotes.appendingConferenceURL(
                notes: markdownDescription,
                conferenceURL: conferenceURL
            )
            return CalendarOutlookIngestSnapshot(
                remoteID: remoteID,
                title: title,
                start: start,
                end: end,
                isAllDay: isAllDay,
                location: loc,
                notes: notes
            )
        }

        let mapUpdates = (try? CalendarIntegrationAccess.syncIngest?.ingestOutlookSnapshots(
            snapshots: snapshots,
            calendarID: calendarID,
            currentMap: currentMap
        )) ?? [:]

        var newMap = outlookSyncMap
        for (k, v) in mapUpdates { newMap[k] = v }
        outlookSyncMap = newMap
        notifyCalendarDidChangeMainActor()
        _ = syncNotificationID
    }

    func synciCloudEventsToStore(
        _ events: [iCloudEventData], calendarURLString: String
    ) async {
        let currentMap = iCloudSyncMap
        let snapshots = events.map { ev in
            CalendarICloudIngestSnapshot(
                mapKey: "\(calendarURLString)||\(ev.uid)",
                providerEventId: ev.uid,
                title: ev.summary,
                start: ev.startDate,
                end: ev.endDate,
                isAllDay: ev.isAllDay,
                location: ev.location,
                notes: ev.notes
            )
        }

        let mapUpdates = (try? CalendarIntegrationAccess.syncIngest?.ingestICloudSnapshots(
            snapshots: snapshots,
            currentMap: currentMap
        )) ?? [:]

        var newMap = iCloudSyncMap
        for (k, v) in mapUpdates { newMap[k] = v }
        iCloudSyncMap = newMap
        notifyCalendarDidChangeMainActor()
    }

    func purgeiCloudEventsFromStore() {
        let ids = iCloudSyncMap.values.compactMap { UUID(uuidString: $0) }
        iCloudSyncMap = [:]
        guard !ids.isEmpty else { return }
        CalendarPersistenceAccess.persistence?.bulkDeleteCalendarEvents(withUUIDs: ids)
        notifyCalendarDidChangeMainActor()
    }
}
