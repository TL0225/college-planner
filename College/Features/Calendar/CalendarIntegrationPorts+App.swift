import CollegeCalendar
import Foundation

@MainActor
final class CalendarSyncIngestPortAdapter: CalendarSyncIngestPort {
    static let shared = CalendarSyncIngestPortAdapter()

    func ingestAppleSnapshots(
        snapshots: [CalendarAppleIngestSnapshot],
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>
    ) async throws -> [String: String] {
        try await BackgroundServiceOnDemand.runThrowing(id: "calendar_sync_ingest") {
            let mapped = snapshots.map {
                CalendarSyncIngestService.AppleEventSnapshot(
                    externalID: $0.externalID,
                    title: $0.title,
                    start: $0.start,
                    end: $0.end,
                    isAllDay: $0.isAllDay,
                    location: $0.location,
                    notes: $0.notes,
                    urlString: $0.urlString,
                    calendarIdentifier: $0.calendarIdentifier,
                    localUUIDFromURL: $0.localUUIDFromURL,
                    recurrenceRule: $0.recurrenceRule
                )
            }
            return try await CalendarSyncIngestService.ingestAppleSnapshots(
                snapshots: mapped,
                currentMap: currentMap,
                mappedLocalIDsLower: mappedLocalIDsLower
            )
        }
    }

    func ingestGoogleSnapshots(
        snapshots: [CalendarGoogleIngestSnapshot],
        calendarID: String,
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        deletedTombstones: Set<String>
    ) async throws -> CalendarGoogleIngestResult {
        try await BackgroundServiceOnDemand.runThrowing(id: "calendar_sync_ingest") {
            let mapped = snapshots.map {
                CalendarSyncIngestService.GoogleEventSnapshot(
                    remoteKey: $0.remoteKey,
                    legacyKey: $0.legacyKey,
                    providerEventId: $0.providerEventId,
                    title: $0.title,
                    start: $0.start,
                    end: $0.end,
                    isAllDay: $0.isAllDay,
                    location: $0.location,
                    notes: $0.notes,
                    status: $0.status,
                    customColorHex: $0.customColorHex,
                    recurrenceRule: $0.recurrenceRule,
                    attendeesJSON: $0.attendeesJSON,
                    isCancelled: $0.isCancelled
                )
            }
            let result = try await CalendarSyncIngestService.ingestGoogleSnapshots(
                snapshots: mapped,
                calendarID: calendarID,
                currentMap: currentMap,
                mappedLocalIDsLower: mappedLocalIDsLower,
                deletedTombstones: deletedTombstones
            )
            return CalendarGoogleIngestResult(
                mapUpdates: result.mapUpdates,
                mapRemovals: result.mapRemovals,
                cancelledRemoteKeys: result.cancelledRemoteKeys,
                newCount: result.newCount
            )
        }
    }

    func ingestOutlookSnapshots(
        snapshots: [CalendarOutlookIngestSnapshot],
        calendarID: String,
        currentMap: [String: String]
    ) async throws -> [String: String] {
        try await BackgroundServiceOnDemand.runThrowing(id: "calendar_sync_ingest") {
            let mapped = snapshots.map {
                CalendarSyncIngestService.OutlookEventSnapshot(
                    remoteID: $0.remoteID,
                    title: $0.title,
                    start: $0.start,
                    end: $0.end,
                    isAllDay: $0.isAllDay,
                    location: $0.location,
                    notes: $0.notes
                )
            }
            return try await CalendarSyncIngestService.ingestOutlookSnapshots(
                snapshots: mapped,
                calendarID: calendarID,
                currentMap: currentMap
            )
        }
    }

    func ingestICloudSnapshots(
        snapshots: [CalendarICloudIngestSnapshot],
        currentMap: [String: String]
    ) async throws -> [String: String] {
        try await BackgroundServiceOnDemand.runThrowing(id: "calendar_sync_ingest") {
            let mapped = snapshots.map {
                CalendarSyncIngestService.ICloudEventSnapshot(
                    mapKey: $0.mapKey,
                    providerEventId: $0.providerEventId,
                    title: $0.title,
                    start: $0.start,
                    end: $0.end,
                    isAllDay: $0.isAllDay,
                    location: $0.location,
                    notes: $0.notes,
                    localUUIDFromICal: $0.localUUIDFromICal
                )
            }
            return try await CalendarSyncIngestService.ingestICloudSnapshots(
                snapshots: mapped,
                currentMap: currentMap
            )
        }
    }
}

@MainActor
final class CalendarCourseLinkerPortAdapter: CalendarCourseLinkerPort {
    static let shared = CalendarCourseLinkerPortAdapter()

    func scanAndLink() async {
        await CalendarCourseLinker.shared.scanAndLink()
    }
}

@MainActor
final class GoogleCalendarDebugLogPortAdapter: GoogleCalendarDebugLogPort {
    static let shared = GoogleCalendarDebugLogPortAdapter()

    func ensureFileExists() {
        GoogleDebugLog.ensureFileExists()
    }

    func fileURL() -> URL {
        GoogleDebugLog.fileURL() ?? URL(fileURLWithPath: "/tmp/college-google-debug.log")
    }
}

extension CalendarPersistencePortBootstrap {
    @MainActor
    static func wireIntegrationPorts() {
        CalendarIntegrationAccess.syncIngest = CalendarSyncIngestPortAdapter.shared
        CalendarIntegrationAccess.courseLinker = CalendarCourseLinkerPortAdapter.shared
        CalendarIntegrationAccess.googleDebugLog = GoogleCalendarDebugLogPortAdapter.shared
    }
}
