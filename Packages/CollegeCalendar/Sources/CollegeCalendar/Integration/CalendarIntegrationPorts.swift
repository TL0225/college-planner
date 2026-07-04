import Foundation

public struct CalendarAppleIngestSnapshot: Sendable {
    public let externalID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let urlString: String?
    public let calendarIdentifier: String?
    public let localUUIDFromURL: UUID?
    public let recurrenceRule: String?

    public init(
        externalID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        urlString: String?,
        calendarIdentifier: String?,
        localUUIDFromURL: UUID?,
        recurrenceRule: String? = nil
    ) {
        self.externalID = externalID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.urlString = urlString
        self.calendarIdentifier = calendarIdentifier
        self.localUUIDFromURL = localUUIDFromURL
        self.recurrenceRule = recurrenceRule
    }
}

public struct CalendarGoogleIngestSnapshot: Sendable {
    public let remoteKey: String
    public let legacyKey: String
    public let providerEventId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let status: String?
    public let customColorHex: String?
    public let recurrenceRule: String?
    public let attendeesJSON: String?
    public let isCancelled: Bool

    public init(
        remoteKey: String,
        legacyKey: String,
        providerEventId: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        status: String?,
        customColorHex: String?,
        recurrenceRule: String?,
        attendeesJSON: String?,
        isCancelled: Bool
    ) {
        self.remoteKey = remoteKey
        self.legacyKey = legacyKey
        self.providerEventId = providerEventId
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.status = status
        self.customColorHex = customColorHex
        self.recurrenceRule = recurrenceRule
        self.attendeesJSON = attendeesJSON
        self.isCancelled = isCancelled
    }
}

public struct CalendarGoogleIngestResult: Sendable {
    public let mapUpdates: [String: String]
    public let mapRemovals: [String]
    public let cancelledRemoteKeys: [String]
    public let newCount: Int

    public init(
        mapUpdates: [String: String],
        mapRemovals: [String],
        cancelledRemoteKeys: [String],
        newCount: Int
    ) {
        self.mapUpdates = mapUpdates
        self.mapRemovals = mapRemovals
        self.cancelledRemoteKeys = cancelledRemoteKeys
        self.newCount = newCount
    }
}

public struct CalendarOutlookIngestSnapshot: Sendable {
    public let remoteID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?

    public init(
        remoteID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?
    ) {
        self.remoteID = remoteID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

public struct CalendarICloudIngestSnapshot: Sendable {
    public let mapKey: String
    public let providerEventId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let localUUIDFromICal: UUID?

    public init(
        mapKey: String,
        providerEventId: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        localUUIDFromICal: UUID? = nil
    ) {
        self.mapKey = mapKey
        self.providerEventId = providerEventId
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.localUUIDFromICal = localUUIDFromICal
    }
}

@MainActor
public protocol CalendarSyncIngestPort: AnyObject {
    func ingestAppleSnapshots(
        snapshots: [CalendarAppleIngestSnapshot],
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>
    ) async throws -> [String: String]

    func ingestGoogleSnapshots(
        snapshots: [CalendarGoogleIngestSnapshot],
        calendarID: String,
        currentMap: [String: String],
        mappedLocalIDsLower: Set<String>,
        deletedTombstones: Set<String>
    ) async throws -> CalendarGoogleIngestResult

    func ingestOutlookSnapshots(
        snapshots: [CalendarOutlookIngestSnapshot],
        calendarID: String,
        currentMap: [String: String]
    ) async throws -> [String: String]

    func ingestICloudSnapshots(
        snapshots: [CalendarICloudIngestSnapshot],
        currentMap: [String: String]
    ) async throws -> [String: String]
}

public enum CalendarSyncIngestNotes {
    public static func appendingConferenceURL(notes: String?, conferenceURL: String?) -> String? {
        guard let url = conferenceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty
        else { return notes }
        if let notes, notes.contains(url) { return notes }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return notes + "\n\n" + url
        }
        return url
    }
}

@MainActor
public protocol CalendarCourseLinkerPort: AnyObject {
    func scanAndLink() async
}

@MainActor
public protocol GoogleCalendarDebugLogPort: AnyObject {
    func ensureFileExists()
    func fileURL() -> URL
}

@MainActor
public enum CalendarIntegrationAccess {
    public static weak var syncIngest: (any CalendarSyncIngestPort)?
    public static weak var courseLinker: (any CalendarCourseLinkerPort)?
    public static weak var googleDebugLog: (any GoogleCalendarDebugLogPort)?
}
