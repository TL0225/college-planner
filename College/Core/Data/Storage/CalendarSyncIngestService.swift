// CalendarSyncIngestService.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppleEventSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Apple/Google/Outlook/iCloud calendar sync ingest into local store (Phase 7f).
@MainActor
enum CalendarSyncIngestService {
    struct AppleEventSnapshot: Sendable {
        let externalID: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
        let urlString: String?
        let calendarIdentifier: String?
        let localUUIDFromURL: UUID?
    }

    struct GoogleEventSnapshot: Sendable {
        let remoteKey: String
        let legacyKey: String
        let providerEventId: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
        let status: String?
        let customColorHex: String?
        let recurrenceRule: String?
        let attendeesJSON: String?
        let isCancelled: Bool
    }

    struct GoogleIngestResult: Sendable {
        let mapUpdates: [String: String]
        let mapRemovals: [String]
        let cancelledRemoteKeys: [String]
        let newCount: Int
    }

    struct OutlookEventSnapshot: Sendable {
        let remoteID: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
    }

    struct ICloudEventSnapshot: Sendable {
        let mapKey: String
        let providerEventId: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
    }

    static func isCollegeAppManagedEvent(providerSource: String?) -> Bool {
        providerSource == "CollegeApp"
    }

    static func notesAppendingConferenceURL(notes: String?, conferenceURL: String?) -> String? {
        guard let url = conferenceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty
        else { return notes }
        if let notes, notes.contains(url) { return notes }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return notes + "\n\n" + url
        }
        return url
    }

    static func ingestAppleSnapshots(
        snapshots: [AppleEventSnapshot],
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        store: AppDataStore = .shared
    ) throws -> [String: String] {
        let repo = CalendarRepository(context: store.profileContext)
        let ctx = store.profileContext
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            if let extracted = snap.localUUIDFromURL { return extracted }
            return currentMap[snap.externalID].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? repo.fetchCalendarEvent(id: uuid) {
                preFetched[uuid] = event
            }
        }

        func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
            if let cached = preFetched[uuid] { return cached }
            return try? repo.fetchCalendarEvent(id: uuid)
        }

        for snap in snapshots {
            let externalID = snap.externalID
            let title = snap.title
            let start = snap.start
            let end = snap.end
            let isAllDay = snap.isAllDay
            let location = snap.location
            let notes = snap.notes

            var localUUID: UUID?
            if let extracted = snap.localUUIDFromURL {
                localUUID = extracted
            } else if let mapped = currentMap[externalID], let uuid = UUID(uuidString: mapped) {
                localUUID = uuid
            }

            if let localUUID, let local = fetchLocalEvent(uuid: localUUID) {
                let needsUpdate = local.title != title || local.startDate != start || local.endDate != end
                    || local.allDay != isAllDay || local.location != location || local.notes != notes
                if needsUpdate {
                    _ = try repo.upsertCalendarEvent(
                        id: local.id,
                        title: title.isEmpty ? "Event" : title,
                        startDate: start,
                        endDate: end,
                        allDay: isAllDay,
                        notes: notes,
                        location: location,
                        providerSource: isCollegeAppManagedEvent(providerSource: local.providerSource)
                            ? local.providerSource : "AppleCalendar",
                        providerEventId: externalID,
                        semester: local.semester,
                        course: local.course,
                        createdAt: local.createdAt,
                        lastUpdated: Date()
                    )
                } else if !isCollegeAppManagedEvent(providerSource: local.providerSource) {
                    local.providerSource = "AppleCalendar"
                    local.providerEventId = externalID
                    local.lastUpdated = Date()
                }
                updates[externalID] = localUUID.uuidString
                continue
            }

            if let reusable = findReusableUnmappedLocalEvent(
                ctx: ctx,
                title: title,
                isAllDay: isAllDay,
                start: start,
                end: end,
                mappedLocalIDsLower: mappedLocalIDsLower
            ) {
                _ = try repo.upsertCalendarEvent(
                    id: reusable.id,
                    title: reusable.title,
                    startDate: start,
                    endDate: end,
                    allDay: isAllDay,
                    notes: notes,
                    location: location,
                    providerSource: "AppleCalendar",
                    providerEventId: externalID,
                    semester: nil,
                    course: nil,
                    createdAt: reusable.createdAt,
                    lastUpdated: Date()
                )
                updates[externalID] = reusable.id.uuidString
                continue
            }

            let newID = UUID()
            _ = try repo.upsertCalendarEvent(
                id: newID,
                title: title.isEmpty ? "Event" : title,
                startDate: start,
                endDate: end,
                allDay: isAllDay,
                notes: notes,
                location: location,
                providerSource: "AppleCalendar",
                providerEventId: externalID,
                semester: nil,
                course: nil
            )
            updates[externalID] = newID.uuidString
        }

        try store.profileSave()
        return updates
    }

    static func ingestGoogleSnapshots(
        snapshots: [GoogleEventSnapshot],
        calendarID: String,
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        deletedTombstones: Set<String>,
        store: AppDataStore = .shared
    ) throws -> GoogleIngestResult {
        let repo = CalendarRepository(context: store.profileContext)
        let ctx = store.profileContext
        var mapUpdates: [String: String] = [:]
        var mapRemovals: [String] = []
        var cancelledRemoteKeys: [String] = []
        var newCount = 0

        let batchLookupUUIDs: [UUID] = snapshots.compactMap { snap in
            guard !snap.isCancelled else { return nil }
            let localStr = currentMap[snap.remoteKey]
                ?? (calendarID == "primary" ? currentMap[snap.legacyKey] : nil)
            return localStr.flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in batchLookupUUIDs {
            if let event = try? repo.fetchCalendarEvent(id: uuid) {
                preFetched[uuid] = event
            }
        }

        var unmappedLocalByTitle: [String: [CalendarEvent]] = [:]
        var unmappedDescriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.course == nil && event.semester == nil
            }
        )
        unmappedDescriptor.fetchLimit = 5000
        if let unmapped = try? ctx.fetch(unmappedDescriptor) {
            for ev in unmapped {
                let key = ev.title.lowercased()
                unmappedLocalByTitle[key, default: []].append(ev)
            }
        }

        func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
            if let cached = preFetched[uuid] { return cached }
            return try? repo.fetchCalendarEvent(id: uuid)
        }

        func findReusable(title: String, isAllDay: Bool, start: Date, end: Date) -> CalendarEvent? {
            let candidates = unmappedLocalByTitle[title.lowercased()] ?? []
            for candidate in candidates {
                guard candidate.allDay == isAllDay else { continue }
                guard abs(candidate.startDate.timeIntervalSince(start)) <= 1 else { continue }
                guard abs(candidate.endDate.timeIntervalSince(end)) <= 1 else { continue }
                guard candidate.course == nil, candidate.semester == nil else { continue }
                let cid = candidate.id.uuidString.lowercased()
                guard !mappedLocalIDsLower.contains(cid) else { continue }
                return candidate
            }
            return nil
        }

        for snap in snapshots {
            if snap.isCancelled {
                let mappedStr = currentMap[snap.remoteKey]
                    ?? (calendarID == "primary" ? currentMap[snap.legacyKey] : nil)
                if let uuidStr = mappedStr, let uuid = UUID(uuidString: uuidStr) {
                    try? repo.deleteCalendarEvent(id: uuid)
                }
                mapRemovals.append(snap.remoteKey)
                if calendarID == "primary" { mapRemovals.append(snap.legacyKey) }
                cancelledRemoteKeys.append(snap.remoteKey)
                continue
            }

            if deletedTombstones.contains(snap.remoteKey)
                || (calendarID == "primary" && deletedTombstones.contains(snap.legacyKey))
            {
                continue
            }

            let title = snap.title
            let mappedLocalIDString =
                currentMap[snap.remoteKey]
                ?? (calendarID == "primary" ? currentMap[snap.legacyKey] : nil)

            if currentMap[snap.remoteKey] == nil, calendarID == "primary",
               currentMap[snap.legacyKey] != nil, let mappedLocalIDString
            {
                mapUpdates[snap.remoteKey] = mappedLocalIDString
                mapRemovals.append(snap.legacyKey)
            }

            let providerSource = "Google"
            if let localIDString = mappedLocalIDString,
               let uuid = UUID(uuidString: localIDString),
               let local = fetchLocalEvent(uuid: uuid)
            {
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
                let resolvedProvider = keepsCollegeOwnership ? local.providerSource : providerSource
                _ = try repo.upsertCalendarEvent(
                    id: local.id,
                    title: title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: resolvedProvider,
                    providerEventId: snap.providerEventId,
                    customColorHex: snap.customColorHex,
                    recurrenceRule: snap.recurrenceRule,
                    attendeesJSON: snap.attendeesJSON,
                    semester: local.semester,
                    course: local.course,
                    createdAt: local.createdAt,
                    lastUpdated: Date()
                )
                mapUpdates[snap.remoteKey] = localIDString
                continue
            }

            if let reusable = findReusable(
                title: title,
                isAllDay: snap.isAllDay,
                start: snap.start,
                end: snap.end
            ) {
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: reusable.providerSource)
                _ = try repo.upsertCalendarEvent(
                    id: reusable.id,
                    title: title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: keepsCollegeOwnership ? reusable.providerSource : providerSource,
                    providerEventId: snap.providerEventId,
                    customColorHex: snap.customColorHex,
                    recurrenceRule: snap.recurrenceRule,
                    attendeesJSON: snap.attendeesJSON,
                    semester: reusable.semester,
                    course: reusable.course,
                    createdAt: reusable.createdAt,
                    lastUpdated: Date()
                )
                mapUpdates[snap.remoteKey] = reusable.id.uuidString
                continue
            }

            let newID = UUID()
            _ = try repo.upsertCalendarEvent(
                id: newID,
                title: title,
                startDate: snap.start,
                endDate: snap.end,
                allDay: snap.isAllDay,
                notes: snap.notes,
                location: snap.location,
                providerSource: providerSource,
                providerEventId: snap.providerEventId,
                customColorHex: snap.customColorHex,
                recurrenceRule: snap.recurrenceRule,
                attendeesJSON: snap.attendeesJSON,
                semester: nil,
                course: nil
            )
            mapUpdates[snap.remoteKey] = newID.uuidString
            newCount += 1
        }

        try store.profileSave()
        return GoogleIngestResult(
            mapUpdates: mapUpdates,
            mapRemovals: mapRemovals,
            cancelledRemoteKeys: cancelledRemoteKeys,
            newCount: newCount
        )
    }

    static func ingestOutlookSnapshots(
        snapshots: [OutlookEventSnapshot],
        calendarID: String,
        currentMap: [String: String],
        store: AppDataStore = .shared
    ) throws -> [String: String] {
        let repo = CalendarRepository(context: store.profileContext)
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            currentMap[snap.remoteID].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? repo.fetchCalendarEvent(id: uuid) {
                preFetched[uuid] = event
            }
        }

        for snap in snapshots {
            let notes = snap.notes
            if let idStr = currentMap[snap.remoteID], let uuid = UUID(uuidString: idStr),
               let local = preFetched[uuid] ?? (try? repo.fetchCalendarEvent(id: uuid))
            {
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
                _ = try repo.upsertCalendarEvent(
                    id: local.id,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: notes,
                    location: snap.location,
                    providerSource: keepsCollegeOwnership ? local.providerSource : "Outlook",
                    providerEventId: snap.remoteID,
                    semester: local.semester,
                    course: local.course,
                    createdAt: local.createdAt,
                    lastUpdated: Date()
                )
                updates[snap.remoteID] = idStr
            } else {
                let newID = UUID()
                _ = try repo.upsertCalendarEvent(
                    id: newID,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: notes,
                    location: snap.location,
                    providerSource: "Outlook",
                    providerEventId: snap.remoteID,
                    semester: nil,
                    course: nil
                )
                updates[snap.remoteID] = newID.uuidString
            }
        }

        try store.profileSave()
        return updates
    }

    static func ingestICloudSnapshots(
        snapshots: [ICloudEventSnapshot],
        currentMap: [String: String],
        store: AppDataStore = .shared
    ) throws -> [String: String] {
        let repo = CalendarRepository(context: store.profileContext)
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            currentMap[snap.mapKey].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? repo.fetchCalendarEvent(id: uuid) {
                preFetched[uuid] = event
            }
        }

        for snap in snapshots {
            if let idStr = currentMap[snap.mapKey], let uuid = UUID(uuidString: idStr),
               let local = preFetched[uuid] ?? (try? repo.fetchCalendarEvent(id: uuid))
            {
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
                _ = try repo.upsertCalendarEvent(
                    id: local.id,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: keepsCollegeOwnership ? local.providerSource : "iCloudCalDAV",
                    providerEventId: snap.providerEventId,
                    semester: local.semester,
                    course: local.course,
                    createdAt: local.createdAt,
                    lastUpdated: Date()
                )
                updates[snap.mapKey] = idStr
            } else {
                let newID = UUID()
                _ = try repo.upsertCalendarEvent(
                    id: newID,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: "iCloudCalDAV",
                    providerEventId: snap.providerEventId,
                    semester: nil,
                    course: nil
                )
                updates[snap.mapKey] = newID.uuidString
            }
        }

        try store.profileSave()
        return updates
    }

    private static func findReusableUnmappedLocalEvent(
        ctx: ModelContext,
        title: String,
        isAllDay: Bool,
        start: Date,
        end: Date,
        mappedLocalIDsLower: Set<String>
    ) -> CalendarEvent? {
        let startLower = start.addingTimeInterval(-1)
        let startUpper = start.addingTimeInterval(1)
        let endLower = end.addingTimeInterval(-1)
        let endUpper = end.addingTimeInterval(1)
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.title == title
                    && event.allDay == isAllDay
                    && event.startDate >= startLower && event.startDate <= startUpper
                    && event.endDate >= endLower && event.endDate <= endUpper
                    && event.course == nil
            }
        )
        descriptor.fetchLimit = 8
        guard let matches = try? ctx.fetch(descriptor), !matches.isEmpty else { return nil }
        for candidate in matches {
            let cid = candidate.id.uuidString.lowercased()
            guard !mappedLocalIDsLower.contains(cid) else { continue }
            return candidate
        }
        return nil
    }
}