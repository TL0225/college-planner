// CalendarSyncIngestService.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — AppleEventSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCalendar

/// Apple/Google/Outlook/iCloud calendar sync ingest into local store (Phase 7f).
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
        let recurrenceRule: String?
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
        let localUUIDFromICal: UUID?
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

    static func normalizedAttendeesJSON(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let guests = CalendarEventGuestsCodec.decodeFlexible(raw)
        return CalendarEventGuestsCodec.encode(records: guests)
    }

    private static func plannerLinkFromNotes(
        notes: String?,
        existingCourse: PlannerCourse?,
        context: ModelContext
    ) -> (PlannerCourse?, PlannerSemester?) {
        if let existingCourse {
            return (existingCourse, existingCourse.semester)
        }
        guard let courseID = CalendarSyncNotesMetadata.courseUUID(from: notes) else {
            return (nil, nil)
        }
        guard let course = try? CalendarSyncIngestWriter.fetchCourse(id: courseID, context: context) else {
            return (nil, nil)
        }
        return (course, course.semester)
    }

    static func ingestAppleSnapshots(
        snapshots: [AppleEventSnapshot],
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        store: AppDataStore? = nil
    ) async throws -> [String: String] {
        let container = await MainActor.run {
            (store ?? AppDataStore.shared).profileContainer
        }
        return try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            if let extracted = snap.localUUIDFromURL { return extracted }
            return currentMap[snap.externalID].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx) {
                preFetched[uuid] = event
            }
        }

        func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
            if let cached = preFetched[uuid] { return cached }
            return try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx)
        }

        for snap in snapshots {
            let externalID = snap.externalID
            let title = snap.title
            let start = snap.start
            let end = snap.end
            let isAllDay = snap.isAllDay
            let location = snap.location
            let notes = snap.notes
            let recurrenceRule = snap.recurrenceRule

            var localUUID: UUID?
            if let extracted = snap.localUUIDFromURL {
                localUUID = extracted
            } else if let mapped = currentMap[externalID], let uuid = UUID(uuidString: mapped) {
                localUUID = uuid
            }

            if let localUUID, let local = fetchLocalEvent(uuid: localUUID) {
                let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                    notes: notes,
                    existingCourse: local.course,
                    context: ctx
                )
                let needsUpdate = local.title != title || local.startDate != start || local.endDate != end
                    || local.allDay != isAllDay || local.location != location || local.notes != notes
                    || local.recurrenceRule != recurrenceRule
                if needsUpdate {
                    _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
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
                        recurrenceRule: recurrenceRule,
                        semester: linkedSemester ?? local.semester,
                        course: linkedCourse,
                        createdAt: local.createdAt,
                        lastUpdated: Date(),
                        context: ctx
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
                let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                    notes: notes,
                    existingCourse: reusable.course,
                    context: ctx
                )
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                    id: reusable.id,
                    title: reusable.title,
                    startDate: start,
                    endDate: end,
                    allDay: isAllDay,
                    notes: notes,
                    location: location,
                    providerSource: "AppleCalendar",
                    providerEventId: externalID,
                    recurrenceRule: recurrenceRule,
                    semester: linkedSemester,
                    course: linkedCourse,
                    createdAt: reusable.createdAt,
                lastUpdated: Date(),
                context: ctx
            )
                updates[externalID] = reusable.id.uuidString
                continue
            }

            let newID = UUID()
            let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                notes: notes,
                existingCourse: nil,
                context: ctx
            )
            _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                id: newID,
                title: title.isEmpty ? "Event" : title,
                startDate: start,
                endDate: end,
                allDay: isAllDay,
                notes: notes,
                location: location,
                providerSource: "AppleCalendar",
                providerEventId: externalID,
                recurrenceRule: recurrenceRule,
                semester: linkedSemester,
                course: linkedCourse,
                context: ctx
            )
            updates[externalID] = newID.uuidString
        }

        try ctx.save()
        return updates
        }
    }

    static func ingestGoogleSnapshots(
        snapshots: [GoogleEventSnapshot],
        calendarID: String,
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        deletedTombstones: Set<String>,
        store: AppDataStore? = nil
    ) async throws -> GoogleIngestResult {
        let container = await MainActor.run {
            (store ?? AppDataStore.shared).profileContainer
        }
        return try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
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
            if let event = try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx) {
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

        let neededProviderIDs = Set(
            snapshots.filter { !$0.isCancelled }.map(\.providerEventId)
        )
        var byProviderEventId: [String: CalendarEvent] = [:]
        if !neededProviderIDs.isEmpty {
            var providerDescriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { event in
                    event.providerEventId != nil
                }
            )
            providerDescriptor.fetchLimit = 5000
            if let providerMatches = try? ctx.fetch(providerDescriptor) {
                for event in providerMatches {
                    guard let providerEventId = event.providerEventId,
                          neededProviderIDs.contains(providerEventId),
                          byProviderEventId[providerEventId] == nil
                    else { continue }
                    byProviderEventId[providerEventId] = event
                }
            }
        }

        func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
            if let cached = preFetched[uuid] { return cached }
            return try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx)
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

        func upsertGoogleSnapshot(
            _ snap: GoogleEventSnapshot,
            into local: CalendarEvent,
            preferLocalSchedule: Bool = false
        ) throws -> Bool {
            let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
            let resolvedProvider = keepsCollegeOwnership ? local.providerSource : "Google"
            let attendeesJSON = Self.normalizedAttendeesJSON(snap.attendeesJSON)
            let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                notes: snap.notes,
                existingCourse: local.course,
                context: ctx
            )

            let title: String
            let startDate: Date
            let endDate: Date
            let allDay: Bool
            let location: String?
            let notes: String?
            let customColorHex: String?
            let recurrenceRule: String?
            let mergedAttendeesJSON: String?

            if keepsCollegeOwnership {
                title = local.title
                location = local.location
                notes = local.notes
                customColorHex = local.customColorHex
                if preferLocalSchedule {
                    startDate = local.startDate
                    endDate = local.endDate
                    allDay = local.allDay
                } else {
                    startDate = snap.start
                    endDate = snap.end
                    allDay = snap.isAllDay
                }
                recurrenceRule = local.recurrenceRule ?? snap.recurrenceRule
                mergedAttendeesJSON = attendeesJSON ?? local.attendeesJSON
            } else {
                title = snap.title
                startDate = snap.start
                endDate = snap.end
                allDay = snap.isAllDay
                location = snap.location
                notes = snap.notes
                customColorHex = snap.customColorHex
                recurrenceRule = snap.recurrenceRule
                mergedAttendeesJSON = attendeesJSON
            }

            let needsUpdate = local.title != title || local.startDate != startDate || local.endDate != endDate
                || local.allDay != allDay || local.location != location || local.notes != notes
                || local.customColorHex != customColorHex || local.recurrenceRule != recurrenceRule
                || local.attendeesJSON != mergedAttendeesJSON
                || local.providerEventId != snap.providerEventId
                || local.course?.id != linkedCourse?.id
            if needsUpdate {
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                    id: local.id,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    allDay: allDay,
                    notes: notes,
                    location: location,
                    providerSource: resolvedProvider,
                    providerEventId: snap.providerEventId,
                    customColorHex: customColorHex,
                    recurrenceRule: recurrenceRule,
                    attendeesJSON: mergedAttendeesJSON,
                    semester: linkedSemester ?? local.semester,
                    course: linkedCourse ?? local.course,
                    createdAt: local.createdAt,
                lastUpdated: Date(),
                context: ctx
            )
            } else if !keepsCollegeOwnership {
                local.providerSource = "Google"
                local.providerEventId = snap.providerEventId
                local.lastUpdated = Date()
            }
            return needsUpdate
        }

        for snap in snapshots {
            try Task.checkCancellation()
            if snap.isCancelled {
                let mappedStr = currentMap[snap.remoteKey]
                    ?? (calendarID == "primary" ? currentMap[snap.legacyKey] : nil)
                if let uuidStr = mappedStr, let uuid = UUID(uuidString: uuidStr) {
                    try? CalendarSyncIngestWriter.deleteCalendarEvent(id: uuid, context: ctx)
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
                _ = try upsertGoogleSnapshot(snap, into: local, preferLocalSchedule: true)
                mapUpdates[snap.remoteKey] = localIDString
                continue
            }

            if let byProvider = byProviderEventId[snap.providerEventId] {
                let cid = byProvider.id.uuidString.lowercased()
                let alreadyMappedElsewhere = mappedLocalIDsLower.contains(cid)
                    && mappedLocalIDString?.lowercased() != cid
                if !alreadyMappedElsewhere {
                    _ = try upsertGoogleSnapshot(snap, into: byProvider, preferLocalSchedule: false)
                    mapUpdates[snap.remoteKey] = byProvider.id.uuidString
                    continue
                }
            }

            if let reusable = findReusable(
                title: title,
                isAllDay: snap.isAllDay,
                start: snap.start,
                end: snap.end
            ) {
                _ = try upsertGoogleSnapshot(snap, into: reusable)
                mapUpdates[snap.remoteKey] = reusable.id.uuidString
                continue
            }

            let newID = UUID()
            let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                notes: snap.notes,
                existingCourse: nil,
                context: ctx
            )
            let attendeesJSON = Self.normalizedAttendeesJSON(snap.attendeesJSON)
            _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
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
                attendeesJSON: attendeesJSON,
                semester: linkedSemester,
                course: linkedCourse,
                context: ctx
            )
            mapUpdates[snap.remoteKey] = newID.uuidString
            newCount += 1
        }

        try ctx.save()
        return GoogleIngestResult(
            mapUpdates: mapUpdates,
            mapRemovals: mapRemovals,
            cancelledRemoteKeys: cancelledRemoteKeys,
            newCount: newCount
        )
        }
    }

    static func ingestOutlookSnapshots(
        snapshots: [OutlookEventSnapshot],
        calendarID: String,
        currentMap: [String: String],
        store: AppDataStore? = nil
    ) async throws -> [String: String] {
        let container = await MainActor.run {
            (store ?? AppDataStore.shared).profileContainer
        }
        return try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            currentMap[snap.remoteID].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx) {
                preFetched[uuid] = event
            }
        }

        for snap in snapshots {
            let notes = snap.notes
            if let idStr = currentMap[snap.remoteID], let uuid = UUID(uuidString: idStr),
               let local = preFetched[uuid] ?? (try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx))
            {
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
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
                lastUpdated: Date(),
                context: ctx
            )
                updates[snap.remoteID] = idStr
            } else {
                let newID = UUID()
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
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
                    course: nil,
                    context: ctx
                )
                updates[snap.remoteID] = newID.uuidString
            }
        }

        try ctx.save()
        return updates
        }
    }

    static func ingestICloudSnapshots(
        snapshots: [ICloudEventSnapshot],
        currentMap: [String: String],
        store: AppDataStore? = nil
    ) async throws -> [String: String] {
        let container = await MainActor.run {
            (store ?? AppDataStore.shared).profileContainer
        }
        return try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
        var updates: [String: String] = [:]

        let preFetchUUIDs: [UUID] = snapshots.compactMap { snap in
            if let extracted = snap.localUUIDFromICal { return extracted }
            return currentMap[snap.mapKey].flatMap { UUID(uuidString: $0) }
        }
        var preFetched: [UUID: CalendarEvent] = [:]
        for uuid in preFetchUUIDs {
            if let event = try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx) {
                preFetched[uuid] = event
            }
        }

        let neededProviderIDs = Set(snapshots.map(\.providerEventId))
        var byProviderEventId: [String: CalendarEvent] = [:]
        if !neededProviderIDs.isEmpty {
            var providerDescriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { event in
                    event.providerEventId != nil
                }
            )
            providerDescriptor.fetchLimit = 5000
            if let providerMatches = try? ctx.fetch(providerDescriptor) {
                for event in providerMatches {
                    guard let providerEventId = event.providerEventId,
                          neededProviderIDs.contains(providerEventId),
                          byProviderEventId[providerEventId] == nil
                    else { continue }
                    byProviderEventId[providerEventId] = event
                }
            }
        }

        func fetchLocalEvent(uuid: UUID) -> CalendarEvent? {
            if let cached = preFetched[uuid] { return cached }
            return try? CalendarSyncIngestWriter.fetchCalendarEvent(id: uuid, context: ctx)
        }

        for snap in snapshots {
            var localUUID: UUID?
            if let extracted = snap.localUUIDFromICal {
                localUUID = extracted
            } else if let mapped = currentMap[snap.mapKey], let uuid = UUID(uuidString: mapped) {
                localUUID = uuid
            }

            if let localUUID, let local = fetchLocalEvent(uuid: localUUID) {
                let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                    notes: snap.notes,
                    existingCourse: local.course,
                    context: ctx
                )
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: local.providerSource)
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                    id: local.id,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: keepsCollegeOwnership ? local.providerSource : "iCloudCalDAV",
                    providerEventId: snap.providerEventId,
                    semester: linkedSemester ?? local.semester,
                    course: linkedCourse,
                    createdAt: local.createdAt,
                lastUpdated: Date(),
                context: ctx
            )
                updates[snap.mapKey] = localUUID.uuidString
                continue
            }

            if let byProvider = byProviderEventId[snap.providerEventId] {
                let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                    notes: snap.notes,
                    existingCourse: byProvider.course,
                    context: ctx
                )
                let keepsCollegeOwnership = isCollegeAppManagedEvent(providerSource: byProvider.providerSource)
                _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                    id: byProvider.id,
                    title: snap.title,
                    startDate: snap.start,
                    endDate: snap.end,
                    allDay: snap.isAllDay,
                    notes: snap.notes,
                    location: snap.location,
                    providerSource: keepsCollegeOwnership ? byProvider.providerSource : "iCloudCalDAV",
                    providerEventId: snap.providerEventId,
                    semester: linkedSemester ?? byProvider.semester,
                    course: linkedCourse,
                    createdAt: byProvider.createdAt,
                lastUpdated: Date(),
                context: ctx
            )
                updates[snap.mapKey] = byProvider.id.uuidString
                continue
            }

            let (linkedCourse, linkedSemester) = plannerLinkFromNotes(
                notes: snap.notes,
                existingCourse: nil,
                context: ctx
            )
            let newID = UUID()
            _ = try CalendarSyncIngestWriter.upsertCalendarEvent(
                id: newID,
                title: snap.title,
                startDate: snap.start,
                endDate: snap.end,
                allDay: snap.isAllDay,
                notes: snap.notes,
                location: snap.location,
                providerSource: "iCloudCalDAV",
                providerEventId: snap.providerEventId,
                semester: linkedSemester,
                course: linkedCourse,
                context: ctx
            )
            updates[snap.mapKey] = newID.uuidString
        }

        try ctx.save()
        return updates
        }
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

private enum CalendarSyncIngestWriter {
    static func fetchCalendarEvent(id: UUID, context: ModelContext) throws -> CalendarEvent? {
        var descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func fetchCourse(id: UUID, context: ModelContext) throws -> PlannerCourse? {
        var descriptor = FetchDescriptor<PlannerCourse>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    static func upsertCalendarEvent(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = false,
        notes: String? = nil,
        location: String? = nil,
        providerSource: String? = nil,
        providerEventId: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        attendeesJSON: String? = nil,
        lmsAnnouncementId: String? = nil,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now,
        context: ModelContext
    ) throws -> CalendarEvent {
        let event: CalendarEvent
        if let existing = try fetchCalendarEvent(id: id, context: context) {
            event = existing
        } else {
            event = CalendarEvent(
                id: id,
                title: title,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                createdAt: createdAt,
                lastUpdated: lastUpdated
            )
            context.insert(event)
        }
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.allDay = allDay
        event.notes = notes
        event.location = location
        event.createdAt = createdAt
        event.lastUpdated = lastUpdated
        event.providerSource = providerSource
        event.providerEventId = providerEventId
        event.customColorHex = customColorHex
        event.recurrenceRule = recurrenceRule
        event.attendeesJSON = attendeesJSON
        event.lmsAnnouncementId = lmsAnnouncementId
        event.semester = semester
        event.course = course
        return event
    }

    static func deleteCalendarEvent(id: UUID, context: ModelContext) throws {
        guard let event = try fetchCalendarEvent(id: id, context: context) else { return }
        context.delete(event)
    }
}