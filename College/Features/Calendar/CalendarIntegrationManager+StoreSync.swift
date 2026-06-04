// CalendarIntegrationManager+StoreSync.swift
// Feature: Calendar
// Purpose: Calendar module — GoogleSyncDateParsing.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
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
    // MARK: - Google export (bulk)

    private func exportAllLocalEventsToGoogle(token: String) {
        guard googleStatus == .connected else { return }

        let repo = AppDataStore.shared.calendarRepository
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 10_000
        let events = (try? repo.context.fetch(descriptor)) ?? []

        let snapshots: [LocalEventExportSnapshot] = events.map { event in
            LocalEventExportSnapshot(
                localIDString: event.id.uuidString,
                title: event.title.isEmpty ? "New Event" : event.title,
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.allDay,
                location: event.location,
                notes: event.notes
            )
        }

        #if DEBUG
            debugLog("exportAllLocalEventsToGoogle(): exporting \(snapshots.count) events")
        #endif

        for snap in snapshots {
            enqueuePendingUpsert(localID: snap.localIDString)
            performExport(
                localIDString: snap.localIDString,
                title: snap.title,
                start: snap.start,
                end: snap.end,
                isAllDay: snap.isAllDay,
                location: snap.location,
                notes: snap.notes,
                token: token,
                completion: { [weak self] success in
                    guard success else { return }
                    self?.removePendingUpsert(localID: snap.localIDString)
                }
            )
        }
    }

    // MARK: - Google purge

    func purgeGoogleCalendarEventsFromStoreAndClearState() {
        let mapSnapshot = syncMap
        let localIDs = mapSnapshot.values.compactMap { UUID(uuidString: $0) }

        #if DEBUG
            debugLog(
                "disconnectGoogle(): purging \(localIDs.count) local events belonging to Google calendar"
            )
        #endif

        var idsToDelete = Set(localIDs)
        let repo = AppDataStore.shared.calendarRepository
        let ctx = AppDataStore.shared.profileContext

        var googleFingerprints = Set<String>()
        for uuid in localIDs {
            guard let event = try? repo.fetchCalendarEvent(id: uuid) else { continue }
            googleFingerprints.insert(
                Self.googleEventFingerprint(
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    allDay: event.allDay,
                    location: event.location,
                    notes: event.notes
                )
            )
        }

        if !googleFingerprints.isEmpty {
            var personalDescriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { event in
                    event.course == nil && event.semester == nil
                }
            )
            personalDescriptor.fetchLimit = 10_000
            if let personals = try? ctx.fetch(personalDescriptor) {
                for event in personals {
                    let fp = Self.googleEventFingerprint(
                        title: event.title,
                        start: event.startDate,
                        end: event.endDate,
                        allDay: event.allDay,
                        location: event.location,
                        notes: event.notes
                    )
                    if googleFingerprints.contains(fp) {
                        idsToDelete.insert(event.id)
                    }
                }
            }
        }

        setSyncMap([:])
        deletedIDs = []
        pendingDeletionIDs = []
        pendingUpsertLocalIDs = []

        guard !idsToDelete.isEmpty else {
            notifyCalendarDidChangeMainActor()
            return
        }

        CollegePersistence.shared.bulkDeleteCalendarEvents(withUUIDs: Array(idsToDelete))

        #if DEBUG
            debugLog("disconnectGoogle(): purge complete (deleted=\(idsToDelete.count))")
        #endif
    }

    // MARK: - Google ingest

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

            let result: CalendarSyncIngestService.GoogleIngestResult
            do {
                result = try CalendarSyncIngestService.ingestGoogleSnapshots(
                    snapshots: snapshots,
                    calendarID: calendarID,
                    currentMap: currentMap,
                    mappedLocalIDsLower: mappedLocalIDsLower,
                    deletedTombstones: deletedTombstones
                )
            } catch {
                #if DEBUG
                    self.debugLog("syncGoogleEventsTolocal store: ingest FAILED: \(error)")
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

            if let syncNotificationID = syncNotificationID {
                if result.newCount > 0 {
                    AppNotificationCenter.shared.complete(
                        id: syncNotificationID,
                        title: "Calendar Synced",
                        message:
                            "\(result.newCount) new event\(result.newCount == 1 ? "" : "s") synced from Google Calendar",
                        autoDismissAfter: 4
                    )
                } else {
                    AppNotificationCenter.shared.complete(
                        id: syncNotificationID,
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
    ) -> [CalendarSyncIngestService.GoogleEventSnapshot] {
        items.compactMap { item in
            let remoteKey = googleRemoteKeyForSync(calendarID: calendarID, eventID: item.id)
            let legacyKey = item.id

            if item.status == "cancelled" {
                return CalendarSyncIngestService.GoogleEventSnapshot(
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
            let notes = CalendarSyncIngestService.notesAppendingConferenceURL(
                notes: baseNotes,
                conferenceURL: conferenceURL
            )
            let recurrenceRule = GoogleAttendeeHelper.rrule(from: item.recurrence)
            let attendeesJSON = GoogleAttendeeHelper.encode(item.attendees ?? [])

            return CalendarSyncIngestService.GoogleEventSnapshot(
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

    func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
        try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: uuid)
    }

    func fetchLocalEventsBatch(uuids: [UUID]) -> [UUID: CalendarEvent] {
        guard !uuids.isEmpty else { return [:] }
        let repo = AppDataStore.shared.calendarRepository
        var result: [UUID: CalendarEvent] = [:]
        result.reserveCapacity(uuids.count)
        for uuid in uuids {
            if let event = try? repo.fetchCalendarEvent(id: uuid) {
                result[uuid] = event
            }
        }
        return result
    }

    // MARK: - Outlook ingest

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

        let snapshots: [CalendarSyncIngestService.OutlookEventSnapshot] = items.compactMap { item in
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
            let notes = CalendarSyncIngestService.notesAppendingConferenceURL(
                notes: markdownDescription,
                conferenceURL: conferenceURL
            )
            return CalendarSyncIngestService.OutlookEventSnapshot(
                remoteID: remoteID,
                title: title,
                start: start,
                end: end,
                isAllDay: isAllDay,
                location: loc,
                notes: notes
            )
        }

        let mapUpdates = (try? CalendarSyncIngestService.ingestOutlookSnapshots(
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

    // MARK: - iCloud ingest

    func synciCloudEventsToStore(
        _ events: [iCloudEventData], calendarURLString: String
    ) async {
        let currentMap = iCloudSyncMap
        let snapshots = events.map { ev in
            CalendarSyncIngestService.ICloudEventSnapshot(
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

        let mapUpdates = (try? CalendarSyncIngestService.ingestICloudSnapshots(
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
        CollegePersistence.shared.bulkDeleteCalendarEvents(withUUIDs: ids)
        notifyCalendarDidChangeMainActor()
    }
}
