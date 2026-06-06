// CalendarIntegrationManager.swift
// Feature: Calendar
// Purpose: Calendar module — ConnectedCalendar.
// Data: CollegePersistence / repositories when applicable.

import AuthenticationServices
import Combine
import CryptoKit
import EventKit
import Foundation
import Security
import SwiftUI
import os
import CollegeCalendar

// MARK: - Outlook import (file scope: `DateFormatter` + payload boxes for local store `perform` @Sendable closures)

enum OutlookImportDateFormatters {
    static let fmt1: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        return f
    }()

    static let fmt2: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static let fmtD: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

/// Bridges `[[String: Any]]` into `@Sendable` local store import work.
private final class OutlookGraphItemsBox: @unchecked Sendable {
    let items: [[String: Any]]
    init(_ items: [[String: Any]]) { self.items = items }
}

/// Collects remote→local ID map updates on a local store queue without mutating a captured `[String: String]`.
private final class CalendarSyncMapMutationBox: @unchecked Sendable {
    private var storage: [String: String] = [:]
    func set(_ key: String, _ value: String) { storage[key] = value }
    var snapshot: [String: String] { storage }
}

enum CalendarConnectionStatus: String {
    case disconnected = "CONNECT"
    case connecting = "CONNECTING..."
    case connected = "SYNCED"
}

struct ConnectedCalendar: Identifiable, Hashable {
    let id: String
    let name: String
    let source: String  // "Apple" or "Google"
    let color: Color
    let remoteID: String?
}

@MainActor
class CalendarIntegrationManager: ObservableObject {
    // Singleton likely needed if shared across views, but we'll stick to StateObject injection for now
    // or rely on EnvironmentObject if it's set up that way.

    @Published var googleStatus: CalendarConnectionStatus = {
        UserDefaults.standard.bool(forKey: "GoogleConnected") ? .connected : .disconnected
    }()
    @Published var outlookStatus: CalendarConnectionStatus = .disconnected
    @Published var iCloudStatus: CalendarConnectionStatus = .disconnected
    @Published var appleStatus: CalendarConnectionStatus = {
        AppleCalendarIntegration.isConnected ? .connected : .disconnected
    }()

    @Published var connectedCalendars: [ConnectedCalendar] = [
        ConnectedCalendar(
            id: "Apple:Home", name: "College App", source: "Apple", color: .red, remoteID: nil)
    ]

    @Published var enabledCalendarIDs: Set<String>
    /// Incremented each time any calendar is toggled on/off. Observing this in the
    /// view's calendarKey ensures an immediate data reload without full re-navigation.
    @Published var calendarVisibilityToken: Int = 0

    // ISO8601DateFormatter is thread-safe (immutable after init) — no lock needed.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    // YYYY-MM-DD date-only formatter (withFullDate = "yyyy-MM-dd"), also thread-safe.
    nonisolated(unsafe) private static let ymdFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()

    nonisolated private static func parseISO8601(_ value: String) -> Date? {
        return isoFormatter.date(from: value)
    }

    nonisolated private static func parseYMD(_ value: String) -> Date? {
        return ymdFormatter.date(from: value)
    }

    nonisolated private static func formatISO8601(_ date: Date) -> String {
        return isoFormatter.string(from: date)
    }

    nonisolated private static func formatYMD(_ date: Date) -> String {
        return ymdFormatter.string(from: date)
    }

    #if DEBUG
        nonisolated static let perfLog = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "College",
            category: "CalendarSync"
        )
    #endif

    private let enabledCalendarsKey = "EnabledCalendars"
    private let enabledCalendarsVersionKey = "EnabledCalendarsVersion"
    private let enabledCalendarsVersion: Int = 1
    private let knownGoogleCalendarsKey = "KnownGoogleCalendars"
    private let persistedGoogleCalendarsKey = "PersistedGoogleCalendars"
    private let primaryGoogleCalendarIDKey = "PrimaryGoogleCalendarID"
    private var primaryGoogleCalendarID: String? = nil

    // nonisolated(unsafe): Task.cancel() is Sendable and safe to call from deinit.
    nonisolated(unsafe) private var syncTask: Task<Void, Never>?
    private var isSyncInFlight: Bool = false
    private var queuedSyncRequest: Bool = false
    private var ekStoreChangeDebounce: Task<Void, Never>?
    private var lastAppleSyncAt: Date = .distantPast
    private let minimumAppleSyncInterval: TimeInterval = 45

    // MARK: - Apple Calendar (EventKit)

    let eventStore = EKEventStore()
    nonisolated(unsafe) private var appleEventStoreObserver: NSObjectProtocol?

    // Privacy/security: avoid shared session cookies/caches for Google requests.
    private lazy var secureSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // Fast lookup: local UUID lowercased -> externalID
    private var appleExternalIDByLocalIDLower: [String: String] = [:]
    // Memo-cache: externalID -> "AppleSystem:<calendarIdentifier>" toggle ID.
    // Eliminates per-render EKEventStore.event(withIdentifier:) hits in shouldDisplayEvent.
    private var appleToggleIDByExternalID: [String: String] = [:]

    private func rebuildAppleReverseMap(from map: [String: String]) {
        var next: [String: String] = [:]
        next.reserveCapacity(map.count)
        for (externalID, localID) in map {
            next[localID.lowercased()] = externalID
        }
        appleExternalIDByLocalIDLower = next
        // Preserve cached EKEventStore toggle-ID lookups for externalIDs that are still
        // present in the new map — avoids redundant EKEventStore.event(withIdentifier:) hits.
        let validExternalIDs = Set(next.values)
        appleToggleIDByExternalID = appleToggleIDByExternalID.filter { validExternalIDs.contains($0.key) }
    }

    func setAppleSyncMap(_ map: [String: String]) {
        AppleCalendarIntegration.syncMap = map
        rebuildAppleReverseMap(from: map)
    }

    func appleExternalID(forLocalID localID: String) -> String? {
        let key = localID.lowercased()
        if let v = appleExternalIDByLocalIDLower[key] { return v }
        let m = AppleCalendarIntegration.syncMap
        rebuildAppleReverseMap(from: m)
        return appleExternalIDByLocalIDLower[key]
    }

    private func ensureAppleCalendarsLoadedIfConnected() {
        guard appleStatus == .connected else { return }
        let calendars = loadAppleCalendars()
        if calendars.isEmpty { return }
        // Single assignment fires objectWillChange once instead of twice.
        connectedCalendars = connectedCalendars.filter { $0.source != "AppleSystem" } + calendars
    }

    private func loadAppleCalendars() -> [ConnectedCalendar] {
        guard appleStatus == .connected else { return [] }
        let cals = eventStore.calendars(for: .event)
        let mapped: [ConnectedCalendar] = cals.map { cal in
            let color = Color(
                nsColor: cal.cgColor
                    .flatMap { NSColor(cgColor: $0) }
                    ?? .systemBlue
            )
            return ConnectedCalendar(
                id: "AppleSystem:\(cal.calendarIdentifier)",
                name: cal.title,
                source: "AppleSystem",
                color: color,
                remoteID: cal.calendarIdentifier
            )
        }
        return mapped.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Local (app-managed) calendar management

    private let persistedLocalCalendarsKey = "PersistedLocalCalendars_v1"

    private struct PersistedLocalCalendar: Codable {
        let id: String
        let name: String
        let colorHex: String
    }

    func addLocalCalendar(name: String, colorHex: String) {
        let id = "Apple:\(UUID().uuidString)"
        let cal = ConnectedCalendar(
            id: id, name: name, source: "Apple", color: Color(hex: colorHex), remoteID: nil)
        connectedCalendars.append(cal)
        enabledCalendarIDs.insert(id)
        persistLocalCalendars()
        persistEnabledCalendars()
    }

    func removeLocalCalendar(_ calendar: ConnectedCalendar) {
        guard calendar.source == "Apple",
            calendar.id != "Apple:Home",
            !calendar.id.hasPrefix("Academics:")
        else { return }
        connectedCalendars.removeAll { $0.id == calendar.id }
        enabledCalendarIDs.remove(calendar.id)
        persistLocalCalendars()
        persistEnabledCalendars()
    }

    /// Removes one Google sub-calendar from the app: purges all its events from CollegePersistence,
    /// clears its delta-sync token, and removes it from the sidebar.
    /// Does NOT delete the calendar from Google itself.
    func removeGoogleCalendar(_ calendar: ConnectedCalendar) {
        guard calendar.source == "Google",
              let remoteID = calendar.remoteID
        else { return }

        let separator = Self.googleRemoteKeySeparator
        let prefix = remoteID + separator

        // Collect local UUIDs for every event that came from this calendar.
        let localUUIDs: [UUID] = syncMap.compactMap { (remoteKey, localUUIDStr) in
            guard remoteKey.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: localUUIDStr)
        }

        // Purge events from CollegePersistence.
        if !localUUIDs.isEmpty {
            CollegePersistence.shared.bulkDeleteCalendarEvents(withUUIDs: localUUIDs)
        }

        // Remove entries from sync map.
        var newMap = syncMap
        for key in newMap.keys where key.hasPrefix(prefix) {
            newMap.removeValue(forKey: key)
        }
        setSyncMap(newMap)

        // Clear delta-sync token so a reconnect starts fresh.
        clearGoogleSyncToken(for: remoteID)

        // Remove from sidebar and toggle state.
        connectedCalendars.removeAll { $0.id == calendar.id }
        enabledCalendarIDs.remove(calendar.id)
        persistEnabledCalendars()

        CollegePersistence.shared.notifyCalendarDidChange()
    }

    /// Removes an Apple System calendar from the app sidebar.
    /// Events remain in CollegePersistence but are hidden (their toggleID is no longer enabled).
    func removeAppleSystemCalendar(_ calendar: ConnectedCalendar) {
        guard calendar.source == "AppleSystem" else { return }
        connectedCalendars.removeAll { $0.id == calendar.id }
        enabledCalendarIDs.remove(calendar.id)
        persistEnabledCalendars()
        CollegePersistence.shared.notifyCalendarDidChange()
    }

    /// Removes an Academics course calendar entry from the sidebar and deletes the
    /// underlying CourseEntity (unlinking any associated calendar events).
    func removeAcademicsCourse(_ calendar: ConnectedCalendar) {
        guard calendar.id.hasPrefix("Academics:") else { return }
        let code = String(calendar.id.dropFirst("Academics:".count))
        CollegePersistence.shared.removeAutoLinkedCourse(code: code)
        CollegePersistence.shared.notifyCalendarDidChange()
    }

    private func persistLocalCalendars() {
        let custom =
            connectedCalendars
            .filter {
                $0.source == "Apple" && $0.id != "Apple:Home" && !$0.id.hasPrefix("Academics:")
            }
            .map {
                PersistedLocalCalendar(
                    id: $0.id, name: $0.name, colorHex: $0.color.hexRGBString() ?? "6366f1")
            }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: persistedLocalCalendarsKey)
        }
    }

    func restorePersistedLocalCalendars() {
        guard let data = UserDefaults.standard.data(forKey: persistedLocalCalendarsKey),
            let decoded = try? JSONDecoder().decode([PersistedLocalCalendar].self, from: data)
        else { return }
        let restored: [ConnectedCalendar] = decoded.map {
            ConnectedCalendar(
                id: $0.id, name: $0.name, source: "Apple", color: Color(hex: $0.colorHex),
                remoteID: nil)
        }
        // Single assignment fires objectWillChange once instead of twice.
        connectedCalendars = connectedCalendars.filter {
            !($0.source == "Apple" && $0.id != "Apple:Home" && !$0.id.hasPrefix("Academics:"))
        } + restored
    }

    // Fast lookup to avoid O(n) scans of syncMap during rendering.
    // Key: local UUID lowercased -> remoteKey (calendarID||eventID)
    private var googleRemoteKeyByLocalIDLower: [String: String] = [:]

    // Store mapping of GoogleEventID -> LocalUUIDString to prevent duplicates
    private let syncMapKey = "GoogleCalendarSyncMap"
    private let deletedIDsKey = "GoogleCalendarDeletedIDs"
    private let pendingDeletionsKey = "GoogleCalendarPendingDeletions"
    private let pendingUpsertsKey = "GoogleCalendarPendingUpserts"
    /// Per-calendar syncToken key prefix. Full key = prefix + calendarID.
    private let syncTokenKeyPrefix = "GoogleCalendarSyncToken_"

    nonisolated private static let googleRemoteKeySeparator = "||"

    private let googleRateLimitUntilKey = "GoogleCalendarRateLimitUntil"
    private let googleRateLimitBackoffSecondsKey = "GoogleCalendarRateLimitBackoffSeconds"
    private let googleSyncRequiresReconnectKey = "GoogleCalendarSyncRequiresReconnect"

    nonisolated private static let googleEventIDAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    nonisolated private static let googleLocalIDExtendedPropertyKey = "college_local_id"

    // In-memory write-through cache — eliminates ≥59 plist round-trips per 60-second sync cycle.
    private var _syncMap: [String: String] = [:]
    var syncMap: [String: String] {
        get { _syncMap }
        set {
            _syncMap = newValue
            UserDefaults.standard.set(newValue, forKey: syncMapKey)
        }
    }

    private func rebuildGoogleReverseMap(from map: [String: String]) {
        var next: [String: String] = [:]
        next.reserveCapacity(map.count)
        for (remoteKey, localID) in map {
            next[localID.lowercased()] = remoteKey
        }
        googleRemoteKeyByLocalIDLower = next
    }

    func setSyncMap(_ map: [String: String]) {
        syncMap = map
        rebuildGoogleReverseMap(from: map)
    }

    // MARK: - Delta Sync Token Helpers

    /// Returns the stored syncToken for a given Google calendarID, or nil if none.
    private func googleSyncToken(for calendarID: String) -> String? {
        UserDefaults.standard.string(forKey: syncTokenKeyPrefix + calendarID)
    }

    /// Persists the next syncToken returned by Google for a given calendarID.
    private func setGoogleSyncToken(_ token: String, for calendarID: String) {
        UserDefaults.standard.set(token, forKey: syncTokenKeyPrefix + calendarID)
    }

    /// Clears the syncToken for a given calendarID (forces full re-sync next cycle).
    private func clearGoogleSyncToken(for calendarID: String) {
        UserDefaults.standard.removeObject(forKey: syncTokenKeyPrefix + calendarID)
    }

    /// Clears all stored syncTokens. Called on disconnect so the next connect starts fresh.
    private func clearAllGoogleSyncTokens() {
        let defaults = UserDefaults.standard
        let prefix = syncTokenKeyPrefix
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private func googleRemoteKey(forLocalID localID: String) -> String? {
        let key = localID.lowercased()
        if let v = googleRemoteKeyByLocalIDLower[key] { return v }
        // If we missed an update (e.g. after app relaunch), rebuild once on-demand.
        let m = syncMap
        rebuildGoogleReverseMap(from: m)
        return googleRemoteKeyByLocalIDLower[key]
    }

    private var _deletedIDs: [String] = []
    var deletedIDs: [String] {
        get { _deletedIDs }
        set {
            _deletedIDs = newValue
            UserDefaults.standard.set(newValue, forKey: deletedIDsKey)
        }
    }

    private var _pendingDeletionIDs: [String] = []
    var pendingDeletionIDs: [String] {
        get { _pendingDeletionIDs }
        set {
            _pendingDeletionIDs = newValue
            UserDefaults.standard.set(newValue, forKey: pendingDeletionsKey)
        }
    }

    // Local UUID strings that need to be (re)exported to Google.
    private var _pendingUpsertLocalIDs: [String] = []
    var pendingUpsertLocalIDs: [String] {
        get { _pendingUpsertLocalIDs }
        set {
            _pendingUpsertLocalIDs = newValue
            UserDefaults.standard.set(newValue, forKey: pendingUpsertsKey)
        }
    }

    private var googleRateLimitUntil: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: googleRateLimitUntilKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue.timeIntervalSince1970, forKey: googleRateLimitUntilKey)
            } else {
                UserDefaults.standard.removeObject(forKey: googleRateLimitUntilKey)
            }
        }
    }

    private var googleRateLimitBackoffSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: googleRateLimitBackoffSecondsKey)
            return v > 0 ? v : 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: googleRateLimitBackoffSecondsKey)
        }
    }

    private var googleSyncRequiresReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: googleSyncRequiresReconnectKey) }
        set { UserDefaults.standard.set(newValue, forKey: googleSyncRequiresReconnectKey) }
    }

    private var googleLastRequestAt: Date = .distantPast
    private let googleMinimumRequestSpacingSeconds: TimeInterval = 0.45
    private let googleInterCalendarSpacingSeconds: TimeInterval = 0.85
    private var googleAdaptiveRequestSpacingSeconds: TimeInterval = 0.45
    private var googleAdaptiveInterCalendarSpacingSeconds: TimeInterval = 0.85
    private var googleAdaptiveBatchSize: Int = 5
    private var didPostGoogleStartupPausedNotice: Bool = false

    init() {
        // Warm up in-memory write-through caches from UserDefaults (read once at launch).
        let ud = UserDefaults.standard
        _syncMap = ud.dictionary(forKey: syncMapKey) as? [String: String] ?? [:]
        _deletedIDs = ud.stringArray(forKey: deletedIDsKey) ?? []
        _pendingDeletionIDs = ud.stringArray(forKey: pendingDeletionsKey) ?? []
        _pendingUpsertLocalIDs = ud.stringArray(forKey: pendingUpsertsKey) ?? []
        _disabledAcademicsIDs = Set(ud.stringArray(forKey: disabledAcademicsKey) ?? [])
        _outlookSyncMap = ud.dictionary(forKey: outlookSyncMapKey) as? [String: String] ?? [:]
        _iCloudSyncMap = ud.dictionary(forKey: iCloudCalDAVSyncMapKey) as? [String: String] ?? [:]

        let persistedEnabled = UserDefaults.standard.stringArray(forKey: enabledCalendarsKey) ?? []
        let persistedVersion = UserDefaults.standard.integer(forKey: enabledCalendarsVersionKey)
        let defaultEnabled: Set<String> = ["Apple:Home", "Apple:School"]

        if persistedEnabled.isEmpty {
            self.enabledCalendarIDs = defaultEnabled
        } else if persistedVersion == 0 {
            // Migration: older builds stored enabled IDs without the local app-managed
            // calendars (Apple:Home / Apple:School). Without seeding these once,
            // newly created local events can be filtered out everywhere.
            var migrated = Set(persistedEnabled)
            migrated.formUnion(defaultEnabled)
            self.enabledCalendarIDs = migrated
            persistEnabledCalendars()
        } else {
            self.enabledCalendarIDs = Set(persistedEnabled)
        }

        // Restore cached Google calendar list (so the picker isn't empty while syncing).
        // Safe because we only surface these when Google is currently marked connected.
        if UserDefaults.standard.bool(forKey: "GoogleConnected") {
            self.primaryGoogleCalendarID = UserDefaults.standard.string(
                forKey: primaryGoogleCalendarIDKey)
            restorePersistedGoogleCalendars()
        }

        // Restore user-created local calendars.
        restorePersistedLocalCalendars()

        // Build the in-memory reverse lookup cache for fast UI filtering.
        rebuildGoogleReverseMap(from: syncMap)
        rebuildAppleReverseMap(from: AppleCalendarIntegration.syncMap)

        if AppleCalendarIntegration.isConnected {
            appleStatus = .connected
            ensureAppleCalendarsLoadedIfConnected()
            observeAppleEventStoreChanges()
            performAppleInitialSync(showNotifications: false)
        }

        if googleStatus == .connected {
            // Do not touch Google Keychain during app startup.
            // Sync will resume when user explicitly reconnects or manually resyncs.
            if !didPostGoogleStartupPausedNotice {
                didPostGoogleStartupPausedNotice = true
                googleStatus = .disconnected
                UserDefaults.standard.set(false, forKey: "GoogleConnected")
                connectedCalendars.removeAll { $0.source == "Google" }
                _ = AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Google Sync Paused",
                    message: "Reconnect Google Calendar to resume sync.",
                    autoDismissAfter: 8
                )
            }
        }
    }

    func sourceCalendarColor(for event: CalendarEvent) -> Color? {
        let localID = event.id.uuidString

        if Self.isCollegeAppManagedEvent(event) {
            let appleID: String = {
                let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !code.isEmpty {
                    return "Academics:\(code.uppercased())"
                }
                return "Apple:Home"
            }()

            if appleID.hasPrefix("Academics:") { return nil }
            return connectedCalendars.first(where: { $0.id == appleID })?.color
        }

        // 1) Google events: derive calendar from syncMap remote key.
        if let remoteKey = googleRemoteKey(forLocalID: localID) {
            let parsed = parseGoogleRemoteKey(remoteKey)
            let toggleID = toggleIDForGoogleCalendarID(parsed.calendarID)
            return connectedCalendars.first(where: { $0.id == toggleID })?.color
        }

        // 2) Apple Calendar events: derive calendar from Apple syncMap.
        if let externalID = appleExternalID(forLocalID: localID),
            let ek = eventStore.event(withIdentifier: externalID)
        {
            let toggleID = "AppleSystem:\(ek.calendar.calendarIdentifier)"
            return connectedCalendars.first(where: { $0.id == toggleID })?.color
        }

        // 3) Local (app-managed) events
        let appleID: String = {
            let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !code.isEmpty {
                return "Academics:\(code.uppercased())"
            }
            return "Apple:Home"
        }()

        // Academics: colors are derived by the sidebar; fall back to nil here.
        if appleID.hasPrefix("Academics:") { return nil }
        return connectedCalendars.first(where: { $0.id == appleID })?.color
    }

    private struct PersistedGoogleCalendar: Codable {
        let id: String
        let name: String
        let backgroundColorHex: String?
    }

    private func persistGoogleCalendars(_ calendars: [PersistedGoogleCalendar]) {
        do {
            let data = try JSONEncoder().encode(calendars)
            UserDefaults.standard.set(data, forKey: persistedGoogleCalendarsKey)
        } catch {
            // Ignore persistence failures.
        }
    }

    private func restorePersistedGoogleCalendars() {
        guard googleStatus == .connected else { return }
        guard let data = UserDefaults.standard.data(forKey: persistedGoogleCalendarsKey) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([PersistedGoogleCalendar].self, from: data)
        else { return }

        let googleCalendars: [ConnectedCalendar] =
            decoded
            .map { item in
                ConnectedCalendar(
                    id: "Google:\(item.id)",
                    name: item.name,
                    source: "Google",
                    color: item.backgroundColorHex.flatMap { Color(hex: $0) } ?? .blue,
                    remoteID: item.id
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Single assignment fires objectWillChange once instead of twice.
        connectedCalendars = connectedCalendars.filter { $0.source != "Google" } + googleCalendars
    }

    // Academics: calendars are opt-out: all are on by default; we only track
    // the ones the user explicitly unchecked.
    private let disabledAcademicsKey = "DisabledAcademicsCalendars_v1"

    private var _disabledAcademicsIDs: Set<String> = []
    private var disabledAcademicsIDs: Set<String> {
        get { _disabledAcademicsIDs }
        set {
            _disabledAcademicsIDs = newValue
            UserDefaults.standard.set(Array(newValue), forKey: disabledAcademicsKey)
        }
    }

    func isCalendarEnabled(_ calendar: ConnectedCalendar) -> Bool {
        if calendar.id.hasPrefix("Academics:") {
            return !disabledAcademicsIDs.contains(calendar.id)
        }
        return enabledCalendarIDs.contains(calendar.id)
    }

    /// Captures toggle/sync maps for off-main calendar cache filtering.
    func makeCacheRebuildVisibilityFilter() -> CalendarVisibilityFilter {
        CalendarVisibilityFilter(
            enabledCalendarIDs: enabledCalendarIDs,
            disabledAcademicsIDs: disabledAcademicsIDs,
            connectedCalendarIDs: Set(connectedCalendars.map(\.id)),
            googleRemoteKeyByLocalIDLower: googleRemoteKeyByLocalIDLower,
            appleExternalIDByLocalIDLower: appleExternalIDByLocalIDLower,
            appleToggleIDByExternalID: appleToggleIDByExternalID,
            primaryGoogleCalendarRemoteID: primaryGoogleCalendarID
        )
    }

    func toggleCalendarEnabled(_ calendar: ConnectedCalendar) {
        if calendar.id.hasPrefix("Academics:") {
            var disabled = disabledAcademicsIDs
            if disabled.contains(calendar.id) {
                disabled.remove(calendar.id)
            } else {
                disabled.insert(calendar.id)
            }
            disabledAcademicsIDs = disabled
        } else if enabledCalendarIDs.contains(calendar.id) {
            enabledCalendarIDs.remove(calendar.id)
            persistEnabledCalendars()
        } else {
            enabledCalendarIDs.insert(calendar.id)
            persistEnabledCalendars()
        }
        // Always bump the token so observers (calendarKey) immediately re-fire reloadCalendarData.
        calendarVisibilityToken &+= 1
    }

    private func persistEnabledCalendars() {
        UserDefaults.standard.set(Array(enabledCalendarIDs), forKey: enabledCalendarsKey)
        UserDefaults.standard.set(enabledCalendarsVersion, forKey: enabledCalendarsVersionKey)
    }

    private func ensureEnabled(_ calendarIDs: [String]) {
        var changed = false
        for id in calendarIDs {
            if !enabledCalendarIDs.contains(id) {
                enabledCalendarIDs.insert(id)
                changed = true
            }
        }
        if changed {
            persistEnabledCalendars()
        }
    }

    nonisolated private func makeGoogleRemoteKey(calendarID: String, eventID: String) -> String {
        "\(calendarID)\(Self.googleRemoteKeySeparator)\(eventID)"
    }

    nonisolated private func parseGoogleRemoteKey(_ key: String) -> (
        calendarID: String, eventID: String
    ) {
        // Back-compat: older builds stored just the eventID (assume primary).
        let parts = key.components(separatedBy: Self.googleRemoteKeySeparator)
        if parts.count >= 2 {
            let calendarID = parts[0]
            let eventID = parts[1...].joined(separator: Self.googleRemoteKeySeparator)
            return (calendarID, eventID)
        }
        return ("primary", key)
    }

    private func googleRecurringSeriesID(fromGoogleEventID eventID: String) -> String? {
        // Google recurring instances typically have IDs like: <base>_<YYYYMMDD...>
        // The base can contain underscores, so split on the last underscore and validate the suffix.
        guard let underscore = eventID.lastIndex(of: "_") else { return nil }
        let base = String(eventID[..<underscore])
        let suffix = String(eventID[eventID.index(after: underscore)...])
        guard suffix.count >= 8 else { return nil }
        let datePrefix = suffix.prefix(8)
        guard datePrefix.allSatisfy({ $0.isNumber }) else { return nil }
        guard !base.isEmpty else { return nil }
        return base
    }

    /// Returns a stable series key for Google recurring instances, suitable for grouping in the UI.
    /// - Note: Returns nil for non-Google events or non-recurring items.
    func googleRecurringSeriesKey(for event: CalendarEvent) -> String? {
        let localID = event.id.uuidString
        guard let remoteKey = googleRemoteKey(forLocalID: localID) else { return nil }
        let parsed = parseGoogleRemoteKey(remoteKey)
        guard let baseEventID = googleRecurringSeriesID(fromGoogleEventID: parsed.eventID) else {
            return nil
        }
        return makeGoogleRemoteKey(calendarID: parsed.calendarID, eventID: baseEventID)
    }

    private func defaultGoogleCalendarID() -> String {
        if let primaryGoogleCalendarID {
            return primaryGoogleCalendarID
        }

        let enabledGoogleIDs =
            connectedCalendars
            .filter { $0.source == "Google" && enabledCalendarIDs.contains($0.id) }
            .compactMap { $0.remoteID }

        return enabledGoogleIDs.first ?? "primary"
    }

    private func toggleIDForGoogleCalendarID(_ calendarID: String) -> String {
        if calendarID == "primary", let primaryGoogleCalendarID {
            return "Google:\(primaryGoogleCalendarID)"
        }
        return "Google:\(calendarID)"
    }

    private nonisolated static func isCollegeAppManagedEvent(_ event: CalendarEvent) -> Bool {
        event.providerSource == "CollegeApp"
    }

    func shouldDisplayEvent(_ event: CalendarEvent) -> Bool {
        let localID = event.id.uuidString

        if Self.isCollegeAppManagedEvent(event) {
            let appleID: String = {
                let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !code.isEmpty {
                    return "Academics:\(code.uppercased())"
                }
                return "Apple:Home"
            }()

            if appleID.hasPrefix("Academics:") {
                return !disabledAcademicsIDs.contains(appleID)
            }

            if connectedCalendars.contains(where: { $0.id == appleID }) {
                return enabledCalendarIDs.contains(appleID)
            }
            return true
        }

        // 1) Google events
        if let remoteKey = googleRemoteKey(forLocalID: localID) {
            let parsed = parseGoogleRemoteKey(remoteKey)
            let toggleID = toggleIDForGoogleCalendarID(parsed.calendarID)

            // If we haven't fetched calendarList yet, don't hide events unexpectedly.
            if !connectedCalendars.contains(where: { $0.id == toggleID }) {
                return true
            }
            guard enabledCalendarIDs.contains(toggleID) else { return false }
            // Also respect per-course visibility toggle (app-local, never synced).
            let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !code.isEmpty {
                let academicsID = "Academics:\(code.uppercased())"
                if disabledAcademicsIDs.contains(academicsID) { return false }
            }
            return true
        }

        // 2) Apple Calendar events
        if let externalID = appleExternalID(forLocalID: localID) {
            // Use memo-cache to avoid calling EKEventStore on every render.
            let toggleID: String
            if let cached = appleToggleIDByExternalID[externalID] {
                toggleID = cached
            } else if let ek = eventStore.event(withIdentifier: externalID) {
                toggleID = "AppleSystem:\(ek.calendar.calendarIdentifier)"
                appleToggleIDByExternalID[externalID] = toggleID
            } else {
                return true
            }
            if !connectedCalendars.contains(where: { $0.id == toggleID }) { return true }
            guard enabledCalendarIDs.contains(toggleID) else { return false }
            // Also respect per-course visibility toggle (app-local, never synced).
            if let course = event.course {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    let academicsID = "Academics:\(code.uppercased())"
                    if disabledAcademicsIDs.contains(academicsID) { return false }
                }
            }
            return true
        }

        // 3) Local (app-managed) events
        let appleID: String = {
            let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !code.isEmpty {
                return "Academics:\(code.uppercased())"
            }
            return "Apple:Home"
        }()

        // Academics: calendars are opt-out — visible unless explicitly disabled.
        if appleID.hasPrefix("Academics:") {
            return !disabledAcademicsIDs.contains(appleID)
        }
        // Only hide local app-managed events when a real UI toggle entry exists.
        // Local app-created events are grouped under the app calendar entry (Apple:Home).
        if connectedCalendars.contains(where: { $0.id == appleID }) {
            return enabledCalendarIDs.contains(appleID)
        }
        return true
    }

    // MARK: - Apple Calendar connect/disconnect

    func connectAppleCalendar() {
        if appleStatus == .connected { return }
        appleStatus = .connecting

        Task { [weak self] in
            guard let self else { return }
            do {
                // Prefer full access when available (needed for two-way sync).
                if #available(macOS 14.0, *) {
                    try await self.eventStore.requestFullAccessToEvents()
                } else {
                    // Older API; still requests events access.
                    try await withCheckedThrowingContinuation {
                        (cont: CheckedContinuation<Void, Error>) in
                        self.eventStore.requestAccess(to: .event) { granted, error in
                            if let error {
                                cont.resume(throwing: error)
                                return
                            }
                            if granted {
                                cont.resume(returning: ())
                            } else {
                                cont.resume(
                                    throwing: NSError(
                                        domain: "EventKit", code: 1,
                                        userInfo: [
                                            NSLocalizedDescriptionKey: "Calendar access denied"
                                        ]))
                            }
                        }
                    }
                }

                await MainActor.run {
                    AppleCalendarIntegration.isConnected = true
                    self.appleStatus = .connected
                    self.ensureAppleCalendarsLoadedIfConnected()

                    // Auto-enable the primary College calendar (created if needed).
                    if let primary = AppleCalendarIntegration.ensurePrimaryCalendar(
                        in: self.eventStore)
                    {
                        let toggleID = "AppleSystem:\(primary.calendarIdentifier)"
                        if !self.enabledCalendarIDs.contains(toggleID) {
                            self.enabledCalendarIDs.insert(toggleID)
                            self.persistEnabledCalendars()
                        }
                    }

                    self.observeAppleEventStoreChanges()
                    self.performAppleInitialSync(showNotifications: true)
                }
            } catch {
                await MainActor.run {
                    AppleCalendarIntegration.isConnected = false
                    self.appleStatus = .disconnected
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Calendar Access Denied",
                        message: error.localizedDescription,
                        autoDismissAfter: 5
                    )
                }
            }
        }
    }

    func disconnectAppleCalendar() {
        AppleCalendarIntegration.isConnected = false
        appleStatus = .disconnected
        connectedCalendars.removeAll(where: { $0.source == "AppleSystem" })
        removeAppleEventStoreObserver()
        purgeAppleCalendarEventsFromStore()
    }

    /// Triggers a manual re-sync of Apple Calendar without re-requesting permissions.
    /// Use this instead of `connectAppleCalendar()` for the RE-SYNC button.
    func resyncAppleCalendarNow() {
        guard appleStatus == .connected else { return }
        performAppleInitialSync(showNotifications: true)
    }

    /// Launch preload hook: warms available calendar sources before the user enters the app shell.
    func preloadForLaunch(
        progress: ((Double) -> Void)? = nil,
        detail: ((String) -> Void)? = nil
    ) async throws {
        detail?("Preparing calendar sources")
        progress?(0.05)

        if AppleCalendarIntegration.isConnected {
            detail?("Loading Apple calendars")
            ensureAppleCalendarsLoadedIfConnected()
            progress?(0.20)

            detail?("Syncing Apple events")
            await syncAppleCalendar(showNotifications: false)
            progress?(0.60)
        } else {
            progress?(0.60)
        }

        // Startup preload intentionally avoids Google auth/token checks to prevent
        // Keychain prompts during app launch.

        detail?("Calendar preload complete")
        progress?(1)
    }

    @MainActor
    func notifyCalendarDidChangeMainActor() {
        CollegePersistence.shared.notifyCalendarDidChange()
    }

    private func purgeAppleCalendarEventsFromStore() {
        let localUUIDs = AppleCalendarIntegration.syncMap.values.compactMap { UUID(uuidString: $0) }
        setAppleSyncMap([:])
        guard !localUUIDs.isEmpty else { return }
        CollegePersistence.shared.bulkDeleteCalendarEvents(withUUIDs: localUUIDs)
        notifyCalendarDidChangeMainActor()
    }

    // MARK: - Apple Calendar sync (two-way)

    private func observeAppleEventStoreChanges() {
        removeAppleEventStoreObserver()
        appleEventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ekStoreChangeDebounce?.cancel()
                self.ekStoreChangeDebounce = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s debounce
                    guard !Task.isCancelled else { return }
                    guard let self, self.appleStatus == .connected else { return }
                    self.performAppleInitialSync(showNotifications: false)
                }
            }
        }
    }

    nonisolated private func removeAppleEventStoreObserver() {
        if let token = appleEventStoreObserver {
            NotificationCenter.default.removeObserver(token)
            appleEventStoreObserver = nil
        }
    }

    deinit {
        removeAppleEventStoreObserver()
        // Cancel all background sync task loops so they don't spin forever after deinit.
        // Task.cancel() is nonisolated and safe to call from any context.
        syncTask?.cancel()
        outlookSyncTask?.cancel()
        iCloudSyncTask?.cancel()
    }

    private func enabledAppleCalendarIdentifiersForSync() -> [String] {
        let ids =
            connectedCalendars
            .filter { $0.source == "AppleSystem" && enabledCalendarIDs.contains($0.id) }
            .compactMap { $0.remoteID }
        return ids
    }

    private func performAppleInitialSync(showNotifications: Bool) {
        Task(priority: .utility) { [weak self] in
            await self?.syncAppleCalendar(showNotifications: showNotifications)
        }
    }

    func syncAppleCalendar(showNotifications: Bool) async {
        guard appleStatus == .connected else { return }

        let now = Date()
        if !showNotifications,
            now.timeIntervalSince(lastAppleSyncAt) < minimumAppleSyncInterval
        {
            return
        }
        lastAppleSyncAt = now

        // Let immediate UI transitions settle before running a silent auto-sync.
        if !showNotifications {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
        }

        let syncNotificationID: UUID? =
            showNotifications
            ? AppNotificationCenter.shared.post(
                kind: .progress,
                title: "Syncing Apple Calendar",
                message: "Importing events…",
                progress: 0.2
            ) : nil

        let calendar = Calendar.current
        // Keep sync window broad enough for common academic timelines while avoiding very large full-store scans.
        let syncPastDays = 180
        let syncFutureDays = 365
        let oneYearAgo = calendar.date(byAdding: .day, value: -syncPastDays, to: now) ?? now
        let oneYearAhead = calendar.date(byAdding: .day, value: syncFutureDays, to: now) ?? now

        let enabledIDs = enabledAppleCalendarIdentifiersForSync()
        guard !enabledIDs.isEmpty else {
            if let syncNotificationID {
                AppNotificationCenter.shared.complete(
                    id: syncNotificationID,
                    title: "Apple Calendar Synced",
                    message: "No enabled calendars to sync",
                    autoDismissAfter: 4
                )
            }
            return
        }

        let calendarsToSync: [EKCalendar] = enabledIDs.compactMap {
            eventStore.calendar(withIdentifier: $0)
        }
        let predicate = eventStore.predicateForEvents(
            withStart: oneYearAgo, end: oneYearAhead, calendars: calendarsToSync)
        let events = eventStore.events(matching: predicate)

        await syncAppleEventsToStore(events, syncNotificationID: syncNotificationID)
    }

    private func syncAppleEventsToStore(_ events: [EKEvent], syncNotificationID: UUID?) async {
        let deletedTombstones = AppleCalendarIntegration.deletedExternalIDs
        let currentMap = AppleCalendarIntegration.syncMap
        let mappedLocalIDsLower = Set(currentMap.values.map { $0.lowercased() })

        let snapshots: [CalendarSyncIngestService.AppleEventSnapshot] = events.compactMap { ek in
            guard let externalID = AppleCalendarIntegration.bestExternalID(for: ek) else {
                return nil
            }
            if deletedTombstones.contains(externalID) { return nil }
            guard let start = ek.startDate, let end = ek.endDate else { return nil }
            let title = (ek.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
            let localUUIDFromURL = ek.url.flatMap {
                AppleCalendarIntegration.extractLocalID(from: $0)
            }
            return CalendarSyncIngestService.AppleEventSnapshot(
                externalID: externalID,
                title: title.isEmpty ? "Event" : title,
                start: start,
                end: end,
                isAllDay: ek.isAllDay,
                location: ek.location,
                notes: ek.notes,
                urlString: ek.url?.absoluteString,
                calendarIdentifier: ek.calendar.calendarIdentifier,
                localUUIDFromURL: localUUIDFromURL
            )
        }

        let mapUpdates: [String: String] = (try? CalendarSyncIngestService.ingestAppleSnapshots(
            snapshots: snapshots,
            currentMap: currentMap,
            mappedLocalIDsLower: mappedLocalIDsLower
        )) ?? [:]

        await MainActor.run {
            var map = AppleCalendarIntegration.syncMap
            for (k, v) in mapUpdates { map[k] = v }
            self.setAppleSyncMap(map)
            CollegePersistence.shared.notifyCalendarDidChange()

            if let syncNotificationID {
                AppNotificationCenter.shared.complete(
                    id: syncNotificationID,
                    title: "Apple Calendar Synced",
                    message: "Apple Calendar is up to date",
                    autoDismissAfter: 3
                )
            }
        }
        // Auto-link Apple-synced events to Academics courses.
        await CalendarCourseLinker.shared.scanAndLink()
    }

    // Phase 7f: `exportEventToAppleCalendar` / `exportEventToGoogle` for `CalendarEvent` live in
    // CalendarIntegrationManager+local storeExport.swift; Google/Outlook/iCloud ingest in +local storeSync.

    func deleteEventFromAppleCalendar(localEventID: UUID) {
        guard appleStatus == .connected else { return }

        if let externalID = appleExternalID(forLocalID: localEventID.uuidString),
            let ek = eventStore.event(withIdentifier: externalID)
        {
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                do {
                    try self.eventStore.remove(ek, span: .thisEvent, commit: true)
                    var tombstones = AppleCalendarIntegration.deletedExternalIDs
                    tombstones.insert(externalID)
                    AppleCalendarIntegration.deletedExternalIDs = tombstones

                    var map = AppleCalendarIntegration.syncMap
                    map.removeValue(forKey: externalID)
                    self.setAppleSyncMap(map)
                    CollegePersistence.shared.notifyCalendarDidChange()
                } catch {
                    // Best-effort.
                }
            }
        }
    }

    #if DEBUG
        private enum DebugFileLogger {
            private static let queue = DispatchQueue(
                label: "College.GoogleCalendar.DebugFileLogger")

            private static var fileURL: URL? {
                GoogleDebugLog.fileURL()
            }

            static func log(_ message: String) {
                queue.async {
                    guard let url = fileURL else { return }

                    GoogleDebugLog.ensureFileExists()

                    let timestamp = CalendarIntegrationManager.formatISO8601(Date())
                    let line = "[\(timestamp)] \(message)\n"

                    do {
                        let data = line.data(using: .utf8) ?? Data()
                        if FileManager.default.fileExists(atPath: url.path) {
                            let handle = try FileHandle(forWritingTo: url)
                            try handle.seekToEnd()
                            try handle.write(contentsOf: data)
                            try handle.close()
                        } else {
                            try data.write(to: url, options: .atomic)
                        }
                    } catch {
                        // Ignore logging failures.
                    }
                }
            }
        }

        nonisolated func debugLog(_ message: String) {
            DebugFileLogger.log(message)
        }
    #endif

    func connectGoogle() {
        // If an earlier attempt didn't launch the auth UI (e.g., session couldn't start),
        // allow retry instead of getting stuck in CONNECTING.
        if googleStatus == .connected { return }
        if googleStatus == .connecting {
            googleStatus = .disconnected
        }

        #if DEBUG
            GoogleDebugLog.ensureFileExists()
            debugLog("connectGoogle() tapped; starting Google OAuth")
        #endif

        googleStatus = .connecting

        GoogleAuthService.shared.signIn { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    #if DEBUG
                        self.debugLog(
                            "Google OAuth sign-in SUCCESS; marking connected and starting initial sync"
                        )
                    #endif
                    self.googleStatus = .connected
                    UserDefaults.standard.set(true, forKey: "GoogleConnected")
                    self.clearGoogleReconnectRequirement()
                    self.primaryGoogleCalendarID = UserDefaults.standard.string(
                        forKey: self.primaryGoogleCalendarIDKey)
                    self.restorePersistedGoogleCalendars()

                    AppNotificationCenter.shared.post(
                        kind: .info,
                        title: "Calendar Connected",
                        message: "Google Calendar sync enabled",
                        autoDismissAfter: 4
                    )

                    // Show notifications for initial sync after connection
                    self.performInitialSync(showNotifications: true)
                    self.startBackgroundSync()
                case .failure(let error):
                    #if DEBUG
                        self.debugLog("Google OAuth sign-in FAILED: \(error.localizedDescription)")
                    #endif
                    self.googleStatus = .disconnected
                    UserDefaults.standard.set(false, forKey: "GoogleConnected")

                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Connection Failed",
                        message: error.localizedDescription,
                        autoDismissAfter: 5
                    )
                }
            }
        }
    }

    func disconnectGoogle() {
        stopBackgroundSync()

        // When unsyncing, purge all locally stored events that belong to the Google calendar.
        // We identify them via the syncMap (GoogleEventID -> local UUID string).
        purgeGoogleCalendarEventsFromStoreAndClearState()

        // Clear delta-sync tokens so the next connect does a full re-sync.
        clearAllGoogleSyncTokens()

        GoogleAuthService.shared.signOut()
        clearGoogleReconnectRequirement()
        googleStatus = .disconnected
        UserDefaults.standard.set(false, forKey: "GoogleConnected")
        // Reset specific google calendars
        connectedCalendars.removeAll { $0.source == "Google" }

        AppNotificationCenter.shared.post(
            kind: .warning,
            title: "Calendar Disconnected",
            message: "Google Calendar sync disabled",
            autoDismissAfter: 4
        )
    }

    // MARK: - Manual Re-sync

    func resyncGoogleNow() {
        guard googleStatus == .connected else {
            #if DEBUG
                debugLog("resyncGoogleNow(): ignored (not connected)")
            #endif
            return
        }

        #if DEBUG
            GoogleDebugLog.ensureFileExists()
            debugLog("resyncGoogleNow(): starting manual resync")
        #endif

        Task { [weak self] in
            await self?.syncGoogle(showNotifications: true)
        }
    }

    struct LocalEventExportSnapshot {
        let localIDString: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
    }

    // Phase 7f: see CalendarIntegrationManager+LegacyPersistence.swift (was L1403-1465)


    private func isGoogleRateLimitedNow() -> Bool {
        guard let until = googleRateLimitUntil else { return false }
        return until > Date()
    }

    private func applyGoogleRateLimitBackoff(from response: HTTPURLResponse?, responseBody: String?)
    {
        // Prefer server hint if present.
        var retryAfterSeconds: Double?
        if let value = response?.value(forHTTPHeaderField: "Retry-After"),
            let s = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            retryAfterSeconds = s
        }

        let now = Date()
        let previous = googleRateLimitBackoffSeconds
        let next = max(15, min(600, previous > 0 ? previous * 2 : 30))
        let chosen = retryAfterSeconds ?? next

        googleRateLimitBackoffSeconds = next
        googleRateLimitUntil = now.addingTimeInterval(chosen)
        googleAdaptiveRequestSpacingSeconds = min(2.4, max(0.6, googleAdaptiveRequestSpacingSeconds * 1.5))
        googleAdaptiveInterCalendarSpacingSeconds = min(3.0, max(1.0, googleAdaptiveInterCalendarSpacingSeconds * 1.5))
        googleAdaptiveBatchSize = max(2, Int(Double(googleAdaptiveBatchSize) * 0.75))

        #if DEBUG
            debugLog(
                "Google rate limit hit; backing off for \(Int(chosen))s (nextBackoff=\(Int(next))s spacing=\(String(format: "%.2f", googleAdaptiveRequestSpacingSeconds)) batch=\(googleAdaptiveBatchSize))"
            )
        #endif

        let retryMessage =
            retryAfterSeconds != nil ? "Retrying in \(Int(chosen))s" : "Retrying in \(Int(chosen))s"
        Task { @MainActor in
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Sync Failed",
                message: "Rate limit exceeded. \(retryMessage)",
                autoDismissAfter: 5
            )
        }
    }

    private func resetGoogleRateLimitBackoff() {
        if googleRateLimitBackoffSeconds != 0 || googleRateLimitUntil != nil {
            googleRateLimitBackoffSeconds = 0
            googleRateLimitUntil = nil
        }

        // Smoothly recover pacing instead of snapping back immediately.
        if googleAdaptiveRequestSpacingSeconds > googleMinimumRequestSpacingSeconds {
            googleAdaptiveRequestSpacingSeconds = max(
                googleMinimumRequestSpacingSeconds,
                googleAdaptiveRequestSpacingSeconds * 0.9
            )
        }
        if googleAdaptiveInterCalendarSpacingSeconds > googleInterCalendarSpacingSeconds {
            googleAdaptiveInterCalendarSpacingSeconds = max(
                googleInterCalendarSpacingSeconds,
                googleAdaptiveInterCalendarSpacingSeconds * 0.9
            )
        }
        if googleAdaptiveBatchSize < 5 {
            googleAdaptiveBatchSize = min(5, googleAdaptiveBatchSize + 1)
        }
    }

    private func markGoogleSyncRequiresReconnect(_ reason: String) {
        guard !googleSyncRequiresReconnect else { return }
        googleSyncRequiresReconnect = true
        #if DEBUG
            debugLog("Google sync suspended until reconnect: \(reason)")
        #endif
    }

    private func clearGoogleReconnectRequirement() {
        if googleSyncRequiresReconnect {
            googleSyncRequiresReconnect = false
        }
    }

    private func isNonRecoverableGoogleAuthError(_ error: Error) -> Bool {
        if let authError = error as? GoogleAuthError {
            switch authError {
            case .missingConfiguration, .invalidConfiguration:
                return true
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("invalid_grant")
            || description.contains("refresh token")
            || description.contains("missing configuration")
    }

    private func handleGoogleReconnectRequired(message: String, syncNotificationID: UUID?) async {
        await MainActor.run {
            self.markGoogleSyncRequiresReconnect(message)
            GoogleAuthService.shared.forceSignOut()

            if let syncNotificationID {
                AppNotificationCenter.shared.update(
                    id: syncNotificationID,
                    title: "Google Reconnect Required",
                    message: message,
                    kind: .error,
                    autoDismissAfter: 6
                )
            } else {
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Google Reconnect Required",
                    message: message,
                    autoDismissAfter: 6
                )
            }
        }
    }

    private func awaitGoogleRequestSlot(maxRateLimitWaitSeconds: TimeInterval = 30) async -> Bool {
        if let until = googleRateLimitUntil, until > Date() {
            let wait = until.timeIntervalSinceNow
            if wait > maxRateLimitWaitSeconds {
                #if DEBUG
                    debugLog("Skipping Google request; rate-limit wait too long (\(Int(wait))s)")
                #endif
                return false
            }
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64((wait + 0.05) * 1_000_000_000))
            }
        }

        let elapsed = Date().timeIntervalSince(googleLastRequestAt)
        let spacing = max(googleMinimumRequestSpacingSeconds, googleAdaptiveRequestSpacingSeconds)
        if elapsed < spacing {
            let remaining = spacing - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        googleLastRequestAt = Date()
        return true
    }

    private func currentGoogleAdaptiveBatchSize(cap: Int) -> Int {
        max(1, min(cap, googleAdaptiveBatchSize))
    }

    // Phase 7f: see CalendarIntegrationManager+LegacyPersistence.swift (was L1617-1731)


    // MARK: - Background Sync

    private func startBackgroundSync() {
        stopBackgroundSync()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.googleStatus == .connected else { continue }
                #if DEBUG
                    self.debugLog("Background Sync Task fired.")
                #endif
                await self.syncGoogle(showNotifications: false)
            }
        }
    }

    nonisolated static func googleEventFingerprint(
        title: String?,
        start: Date?,
        end: Date?,
        allDay: Bool,
        location: String?,
        notes: String?
    ) -> String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let loc = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let n = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Minute-level resolution avoids tiny second differences.
        let s = Int((start ?? .distantPast).timeIntervalSince1970 / 60.0)
        let e = Int((end ?? .distantPast).timeIntervalSince1970 / 60.0)
        return "\(t)|\(allDay ? 1 : 0)|\(s)|\(e)|\(loc)|\(n)"
    }

    private func stopBackgroundSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    private func performInitialSync(showNotifications: Bool = false) {
        Task { [weak self] in
            await self?.syncGoogle(showNotifications: showNotifications)
        }
    }

    // MARK: - Google API Fetch
    func syncGoogle(showNotifications: Bool) async {
        // Ensure we never overlap sync work.
        let syncNotificationID: UUID?
        let shouldRun: Bool

        (syncNotificationID, shouldRun) = await MainActor.run {
            if self.isSyncInFlight {
                self.queuedSyncRequest = true
                return (nil, false)
            }
            self.isSyncInFlight = true

            let id: UUID? =
                showNotifications
                ? AppNotificationCenter.shared.post(
                    kind: .progress,
                    title: "Syncing Calendar",
                    message: "Connecting to Google Calendar...",
                    progress: 0.1
                ) : nil
            return (id, true)
        }

        guard shouldRun else { return }

        #if DEBUG
            let log = Self.perfLog
            let spid = OSSignpostID(log: log)
            os_signpost(
                .begin,
                log: log,
                name: "GoogleSync",
                signpostID: spid,
                "notifications=%{public}d",
                showNotifications ? 1 : 0
            )
            defer { os_signpost(.end, log: log, name: "GoogleSync", signpostID: spid) }
        #endif

        guard googleStatus == .connected else {
            await MainActor.run { self.isSyncInFlight = false }
            return
        }

        if googleSyncRequiresReconnect {
            if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: syncNotificationID,
                        title: "Google Reconnect Required",
                        message: "Reconnect Google Calendar to resume sync.",
                        kind: .warning,
                        autoDismissAfter: 5
                    )
                }
            }
            await MainActor.run { self.isSyncInFlight = false }
            return
        }

        do {
            try Task.checkCancellation()
            let token = try await GoogleAuthService.shared.validAccessToken()
            try Task.checkCancellation()

            if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: syncNotificationID, message: "Fetching calendar list...", progress: 0.3)
                }
            }

            await processPendingGoogleDeletions(token: token)
            await processPendingGoogleUpserts(token: token)
            try Task.checkCancellation()

            await fetchGoogleCalendarList(token: token)
            try Task.checkCancellation()

            if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: syncNotificationID, message: "Importing events...", progress: 0.6)
                }
            }

            await fetchRealGoogleEvents(token: token, syncNotificationID: syncNotificationID)
        } catch is CancellationError {
            // Best-effort: treat cancellation as a silent stop (no error toast).
        } catch {
            #if DEBUG
                debugLog("syncGoogle(): token error: \(error.localizedDescription)")
            #endif
            if isNonRecoverableGoogleAuthError(error) {
                await handleGoogleReconnectRequired(
                    message: "Your Google authorization expired or was revoked. Please reconnect your account.",
                    syncNotificationID: syncNotificationID
                )
            } else if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: syncNotificationID,
                        title: "Sync Failed",
                        message: "Failed to get access token: \(error.localizedDescription)",
                        kind: .error,
                        autoDismissAfter: 5
                    )
                }
            }
        }

        // Auto-link newly synced events to Academics courses + fix the calendarDidChangeToken
        // gap (Google sync never called notifyCalendarDidChange previously).
        await CalendarCourseLinker.shared.scanAndLink()
        CollegePersistence.shared.notifyCalendarDidChange()

        await MainActor.run {
            self.isSyncInFlight = false
            if self.queuedSyncRequest {
                self.queuedSyncRequest = false
                Task { [weak self] in
                    await self?.syncGoogle(showNotifications: false)
                }
            }
        }
    }

    private func enabledGoogleCalendarIDsForSync() -> [String] {
        let google =
            connectedCalendars
            .filter { $0.source == "Google" && enabledCalendarIDs.contains($0.id) }
            .compactMap { $0.remoteID }

        return google
    }

    private func googleCalendarIDsForLookup() -> [String] {
        let google =
            connectedCalendars
            .filter { $0.source == "Google" }
            .compactMap { $0.remoteID }

        return google.isEmpty ? ["primary"] : google
    }

    private func decodeOffMain<T: Decodable & Sendable>(_ type: T.Type, from data: Data)
        async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let decoder = JSONDecoder()
                    let decoded = try decoder.decode(T.self, from: data)
                    continuation.resume(returning: decoded)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fetchGoogleCalendarList(token: String) async {
        guard googleStatus == .connected else { return }
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        #if DEBUG
            debugLog("Fetching Google calendarList: \(url.absoluteString)")
        #endif

        do {
            guard await awaitGoogleRequestSlot() else { return }
            let (data, response) = try await secureSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard (200...299).contains(http.statusCode) else {
                #if DEBUG
                    debugLog("Google calendarList failed status=\(http.statusCode)")
                #endif
                return
            }

            let decoded = try await decodeOffMain(GoogleCalendarListListResponse.self, from: data)

            await MainActor.run {
                let visibleItems = decoded.items.filter { ($0.hidden ?? false) == false }

                let googleCalendars: [ConnectedCalendar] =
                    visibleItems
                    .map { item in
                        let color: Color = {
                            if let hex = item.backgroundColor { return Color(hex: hex) }
                            return .blue
                        }()
                        let summary = (item.summary ?? "Google Calendar").trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        let name = summary.isEmpty ? item.id : summary
                        return ConnectedCalendar(
                            id: "Google:\(item.id)",
                            name: name,
                            source: "Google",
                            color: color,
                            remoteID: item.id
                        )
                    }
                    .sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }

                let primaryID = decoded.items.first(where: { $0.primary ?? false })?.id
                self.primaryGoogleCalendarID = primaryID
                UserDefaults.standard.set(primaryID, forKey: self.primaryGoogleCalendarIDKey)

                // Single assignment fires objectWillChange once instead of twice.
                self.connectedCalendars = self.connectedCalendars.filter { $0.source != "Google" } + googleCalendars

                // Persist the last known list so UI can render immediately after relaunch/resync.
                let persisted = visibleItems.map { item in
                    let summary = (item.summary ?? "Google Calendar").trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    let name = summary.isEmpty ? item.id : summary
                    return PersistedGoogleCalendar(
                        id: item.id, name: name, backgroundColorHex: item.backgroundColor)
                }
                self.persistGoogleCalendars(persisted)

                // Do not override user calendar selections on each sync.
                // Auto-enable only on first connect OR for newly discovered calendars.
                let known = Set(
                    UserDefaults.standard.stringArray(forKey: self.knownGoogleCalendarsKey) ?? [])
                let discovered = Set(visibleItems.map { $0.id })
                let newlyDiscovered = discovered.subtracting(known)
                UserDefaults.standard.set(Array(discovered), forKey: self.knownGoogleCalendarsKey)

                let hasAnyGoogleSelection = self.enabledCalendarIDs.contains(where: {
                    $0.hasPrefix("Google:")
                })

                if !hasAnyGoogleSelection {
                    let selectedIDs = decoded.items
                        .filter { ($0.selected ?? false) || ($0.primary ?? false) }
                        .map { "Google:\($0.id)" }

                    let enableIDs =
                        selectedIDs.isEmpty ? googleCalendars.map { $0.id } : selectedIDs
                    self.ensureEnabled(enableIDs)
                } else if !newlyDiscovered.isEmpty {
                    let autoEnableIDs = decoded.items
                        .filter {
                            newlyDiscovered.contains($0.id)
                                && (($0.selected ?? false) || ($0.primary ?? false))
                        }
                        .map { "Google:\($0.id)" }
                    if !autoEnableIDs.isEmpty {
                        self.ensureEnabled(autoEnableIDs)
                    }
                }
            }
        } catch {
            #if DEBUG
                debugLog("Google calendarList error: \(error.localizedDescription)")
            #endif
        }
    }

    private func fetchRealGoogleEvents(token: String, syncNotificationID: UUID? = nil) async {
        // Fetch all events from 1 year ago to 1 year in the future
        let calendar = Calendar.current
        let now = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: now) ?? now
        let timeMin = Self.formatISO8601(oneYearAgo)
        let timeMax = Self.formatISO8601(oneYearFromNow)

        let calendarIDs = enabledGoogleCalendarIDsForSync()

        guard !calendarIDs.isEmpty else {
            #if DEBUG
                debugLog("Fetching Google Events skipped (no enabled Google calendars)")
            #endif
            if let syncNotificationID = syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: syncNotificationID,
                        title: "Sync Completed",
                        message: "No enabled calendars to sync",
                        kind: .warning,
                        autoDismissAfter: 4
                    )
                }
            }
            return
        }

        for (index, calendarID) in calendarIDs.enumerated() {
            guard !Task.isCancelled else { return }

            await fetchGoogleEvents(
                calendarID: calendarID,
                timeMin: timeMin,
                timeMax: timeMax,
                token: token,
                syncNotificationID: syncNotificationID
            )

            if index < (calendarIDs.count - 1) {
                try? await Task.sleep(
                    nanoseconds: UInt64(max(googleInterCalendarSpacingSeconds, googleAdaptiveInterCalendarSpacingSeconds) * 1_000_000_000)
                )
            }
        }
    }

    private func fetchGoogleEvents(
        calendarID: String,
        timeMin: String,
        timeMax: String,
        token: String,
        syncNotificationID: UUID? = nil
    ) async {
        guard
            let encodedCalendarID = calendarID.addingPercentEncoding(
                withAllowedCharacters: Self.googleEventIDAllowedCharacters)
        else {
            #if DEBUG
                debugLog("fetchGoogleEvents: failed to encode calendarID=\(calendarID)")
            #endif
            return
        }

        // Delta sync: use stored syncToken for incremental updates. Falls back to full range on 410.
        let storedSyncToken = await MainActor.run { googleSyncToken(for: calendarID) }
        var isUsingDeltaSync = (storedSyncToken != nil)

        var pageToken: String? = nil
        var isFirstPage = true

        repeat {
            // Build URL: prefer delta (syncToken), then continuation (pageToken), then full range.
            let pageURLString: String
            if let pt = pageToken, !pt.isEmpty {
                pageURLString =
                    "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events?singleEvents=true&pageToken=\(pt)&maxResults=2500"
            } else if let st = storedSyncToken, !st.isEmpty, isFirstPage, isUsingDeltaSync {
                let encodedST =
                    st.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? st
                pageURLString =
                    "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events?syncToken=\(encodedST)&maxResults=2500"
            } else {
                pageURLString =
                    "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events?singleEvents=true&orderBy=startTime&timeMin=\(timeMin)&timeMax=\(timeMax)&maxResults=2500"
                isUsingDeltaSync = false
            }

            guard let pageURL = URL(string: pageURLString) else { break }

            #if DEBUG
                if isFirstPage {
                    debugLog(
                        "Fetching Google Events\(isUsingDeltaSync ? " (delta)" : " (full)") calendarID=\(calendarID)"
                    )
                }
            #endif

            var request = URLRequest(url: pageURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                guard await awaitGoogleRequestSlot() else { return }
                let (data, response) = try await secureSession.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                    !(200...299).contains(httpResponse.statusCode)
                {
                    let body = String(data: data, encoding: .utf8)

                    // 410 Gone: syncToken expired — clear it and retry with a full range fetch.
                    if httpResponse.statusCode == 410 && isUsingDeltaSync {
                        #if DEBUG
                            debugLog(
                                "Google syncToken expired (410) for calendarID=\(calendarID) — retrying full sync"
                            )
                        #endif
                        await MainActor.run { clearGoogleSyncToken(for: calendarID) }
                        await fetchGoogleEvents(
                            calendarID: calendarID,
                            timeMin: timeMin,
                            timeMax: timeMax,
                            token: token,
                            syncNotificationID: syncNotificationID
                        )
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        await handleGoogleReconnectRequired(
                            message: "Google Calendar authorization expired. Reconnect your account.",
                            syncNotificationID: syncNotificationID
                        )
                        return
                    }
                    if httpResponse.statusCode == 403, body?.contains("rateLimitExceeded") ?? false
                    {
                        applyGoogleRateLimitBackoff(from: httpResponse, responseBody: body)
                    }
                    let errorMessage =
                        httpResponse.statusCode == 403
                        ? "Rate limit exceeded" : "HTTP \(httpResponse.statusCode)"
                    if let syncNotificationID = syncNotificationID {
                        await MainActor.run {
                            AppNotificationCenter.shared.update(
                                id: syncNotificationID,
                                title: "Sync Failed",
                                message: errorMessage,
                                kind: .error,
                                autoDismissAfter: 5
                            )
                        }
                    }
                    return
                }

                // Decode the response — note: delta responses include cancelled events (status="cancelled").
                let listResponse = try await decodeOffMain(
                    GoogleCalendarListResponse.self, from: data)

                #if DEBUG
                    debugLog(
                        "Fetched \(listResponse.items.count) events from calendarID=\(calendarID)\(isUsingDeltaSync ? " (delta)" : "")"
                    )
                #endif

                if isFirstPage, let syncNotificationID = syncNotificationID {
                    await MainActor.run {
                        AppNotificationCenter.shared.update(
                            id: syncNotificationID, message: "Syncing changes...", progress: 0.9)
                    }
                }

                // Persist the nextSyncToken from each page (last page's token is most valuable).
                if let nextSyncToken = listResponse.nextSyncToken {
                    await MainActor.run { setGoogleSyncToken(nextSyncToken, for: calendarID) }
                }

                await syncGoogleEventsToStoreAsync(
                    listResponse.items,
                    calendarID: calendarID,
                    syncNotificationID: isFirstPage ? syncNotificationID : nil
                )

                pageToken = listResponse.nextPageToken
                isFirstPage = false
            } catch {
                #if DEBUG
                    debugLog("Google API events error: \(error.localizedDescription)")
                #endif
                if let syncNotificationID = syncNotificationID {
                    await MainActor.run {
                        AppNotificationCenter.shared.update(
                            id: syncNotificationID,
                            title: "Sync Failed",
                            message: "Network error: \(error.localizedDescription)",
                            kind: .error,
                            autoDismissAfter: 5
                        )
                    }
                }
                return
            }
        } while pageToken != nil && !pageToken!.isEmpty
    }

    func syncGoogleEventsToStoreAsync(
        _ items: [GoogleCalendarEventItem],
        calendarID: String,
        syncNotificationID: UUID? = nil
    ) async {
        await withCheckedContinuation { continuation in
            syncGoogleEventsToStore(
                items, calendarID: calendarID, syncNotificationID: syncNotificationID
            ) {
                continuation.resume()
            }
        }
    }


    func enqueuePendingUpsert(localID: String) {
        var pending = pendingUpsertLocalIDs
        guard !pending.contains(localID) else { return }
        pending.append(localID)
        pendingUpsertLocalIDs = pending
    }

    func removePendingUpsert(localID: String) {
        let pending = pendingUpsertLocalIDs
        let updated = pending.filter { $0 != localID }
        if updated.count != pending.count {
            pendingUpsertLocalIDs = updated
        }
    }

    private func processPendingGoogleUpserts(token: String) async {
        guard googleStatus == .connected else { return }

        if isGoogleRateLimitedNow() {
            #if DEBUG
                if let until = googleRateLimitUntil {
                    debugLog("Skipping pending upserts due to rate limit until \(until)")
                } else {
                    debugLog("Skipping pending upserts due to rate limit")
                }
            #endif
            return
        }

        let pending = pendingUpsertLocalIDs
        guard !pending.isEmpty else { return }

        // Avoid flooding Google when a lot of events are queued.
        let batch = Array(pending.prefix(currentGoogleAdaptiveBatchSize(cap: 5)))

        #if DEBUG
            debugLog("Processing \(batch.count)/\(pending.count) pending Google upserts")
        #endif

        // Pre-fetch all local events in one SQL query instead of N individual fetches.
        let batchUUIDs = batch.compactMap { UUID(uuidString: $0) }
        let batchMap = fetchLocalEventsBatch(uuids: batchUUIDs)

        for localIDString in batch {
            guard let uuid = UUID(uuidString: localIDString) else {
                await MainActor.run { removePendingUpsert(localID: localIDString) }
                continue
            }

            guard let event = batchMap[uuid] ?? fetchLocalEvent(uuid: uuid) else {
                // Event no longer exists locally; drop it from the queue.
                await MainActor.run { removePendingUpsert(localID: localIDString) }
                continue
            }

            // Extract and export without re-enqueueing.
            let title = event.title
            let notes = event.notes
            let location = event.location
            let start = event.startDate
            let end = event.endDate
            let isAllDay = event.allDay

            let success = await performExportAsync(
                localIDString: localIDString,
                title: title,
                start: start,
                end: end,
                isAllDay: isAllDay,
                location: location,
                notes: notes,
                token: token
            )
            if success {
                await MainActor.run { removePendingUpsert(localID: localIDString) }
            }
        }
    }

    func performExport(
        localIDString: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        token: String,
        completion: ((Bool) -> Void)?
    ) {
        Task { [weak self] in
            guard let self else {
                completion?(false)
                return
            }
            let success = await self.performExportAsync(
                localIDString: localIDString,
                title: title,
                start: start,
                end: end,
                isAllDay: isAllDay,
                location: location,
                notes: notes,
                token: token
            )
            completion?(success)
        }
    }

    func performExportAsync(
        localIDString: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        token: String,
        overrideCalendarID: String? = nil
    ) async -> Bool {
        // 2. Prepare Data

        let googleStart: GoogleCalendarDate
        let googleEnd: GoogleCalendarDate

        if isAllDay {
            let sDate = Self.formatYMD(start)
            let eDate = Self.formatYMD(end)
            googleStart = GoogleCalendarDate(dateTime: nil, date: sDate)
            googleEnd = GoogleCalendarDate(dateTime: nil, date: eDate)
        } else {
            let sDate = Self.formatISO8601(start)
            let eDate = Self.formatISO8601(end)
            googleStart = GoogleCalendarDate(dateTime: sDate, date: nil)
            googleEnd = GoogleCalendarDate(dateTime: eDate, date: nil)
        }

        // 3. Check for existing Google remote key
        let currentMap = self.syncMap
        let existingRemoteKey = currentMap.first(where: { $0.value == localIDString })?.key

        let targetCalendarID: String = {
            if let existingRemoteKey {
                return self.parseGoogleRemoteKey(existingRemoteKey).calendarID
            }
            // Use caller-specified calendar if provided, otherwise fall back to default
            return overrideCalendarID ?? self.defaultGoogleCalendarID()
        }()

        // 4. Create Request
        let encodedCalendarID =
            targetCalendarID.addingPercentEncoding(
                withAllowedCharacters: Self.googleEventIDAllowedCharacters) ?? targetCalendarID
        let baseURL = "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
        var url: URL?
        var httpMethod: String

        if let remoteKey = existingRemoteKey {
            let gID = self.parseGoogleRemoteKey(remoteKey).eventID
            // UPDATE
            let encodedID =
                gID.addingPercentEncoding(
                    withAllowedCharacters: Self.googleEventIDAllowedCharacters) ?? gID
            url = URL(string: "\(baseURL)/\(encodedID)")
            httpMethod = "PATCH"
        } else {
            // INSERT
            url = URL(string: baseURL)
            httpMethod = "POST"
        }

        // Only add private extended properties on events we create.
        // Google rejects private extended properties for some event types (e.g. birthdays), and
        // we don't need this tag on PATCH.
        let payload = GoogleEventUpload(
            summary: title,
            location: location,
            description: notes,
            start: googleStart,
            end: googleEnd,
            extendedProperties: (httpMethod == "POST")
                ? GoogleExtendedProperties(privateProperties: [
                    Self.googleLocalIDExtendedPropertyKey: localIDString
                ])
                : nil,
            recurrence: nil,
            conferenceDataVersion: nil
        )

        guard let requestUrl = url else { return false }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            #if DEBUG
                print("Failed to encode event: \(error)")
            #endif
            return false
        }

        // 5. Execute
        do {
            guard await awaitGoogleRequestSlot() else { return false }
            let (data, response) = try await secureSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                #if DEBUG
                    debugLog("Google Export: missing HTTP status")
                #endif
                return false
            }

            let statusCode = http.statusCode
            let responseBody = String(data: data, encoding: .utf8)

            guard (200...299).contains(statusCode) else {
                #if DEBUG
                    debugLog(
                        "Google Export failed (\(httpMethod)) status=\(statusCode) localID=\(localIDString) body=\(responseBody ?? "<none>")"
                    )
                #endif

                if statusCode == 403, responseBody?.contains("rateLimitExceeded") ?? false {
                    applyGoogleRateLimitBackoff(from: http, responseBody: responseBody)
                }

                // Some Google-managed event types reject updates; don't keep retrying forever.
                if statusCode == 400, responseBody?.contains("eventTypeRestriction") ?? false {
                    await MainActor.run { removePendingUpsert(localID: localIDString) }
                    #if DEBUG
                        debugLog(
                            "Dropping pending upsert due to eventTypeRestriction localID=\(localIDString)"
                        )
                    #endif
                }

                return false
            }

            resetGoogleRateLimitBackoff()

            // If created (POST), we get back the ID. Update SyncMap.
            if httpMethod == "POST" {
                if let created = try? await decodeOffMain(
                    GoogleCreatedEventResponse.self, from: data)
                {
                    await MainActor.run {
                        self.updateSyncMap(
                            calendarID: targetCalendarID, eventID: created.id,
                            localID: localIDString)
                    }
                    #if DEBUG
                        debugLog(
                            "Google Export success (POST). GoogleID=\(created.id) localID=\(localIDString)"
                        )
                    #endif
                } else {
                    #if DEBUG
                        debugLog(
                            "Google Export success (POST) but could not decode response; localID=\(localIDString)"
                        )
                    #endif
                }
            } else {
                #if DEBUG
                    debugLog(
                        "Google Export success (\(httpMethod)). localID=\(localIDString) status=\(statusCode)"
                    )
                #endif
            }

            return true
        } catch {
            #if DEBUG
                debugLog("Google Export network error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func updateSyncMap(calendarID: String, eventID: String, localID: String) {
        var map = self.syncMap
        map[makeGoogleRemoteKey(calendarID: calendarID, eventID: eventID)] = localID
        self.setSyncMap(map)
    }

    // MARK: - Deletion

    private func enqueuePendingDeletion(remoteKey: String) {
        var pending = pendingDeletionIDs
        guard !pending.contains(remoteKey) else { return }
        pending.append(remoteKey)
        pendingDeletionIDs = pending
    }

    private func removePendingDeletion(remoteKey: String) {
        let pending = pendingDeletionIDs
        let updated = pending.filter { $0 != remoteKey }
        if updated.count != pending.count {
            pendingDeletionIDs = updated
        }
    }

    private func processPendingGoogleDeletions(token: String) async {
        guard googleStatus == .connected else { return }

        if isGoogleRateLimitedNow() {
            #if DEBUG
                if let until = googleRateLimitUntil {
                    debugLog("Skipping pending deletions due to rate limit until \(until)")
                } else {
                    debugLog("Skipping pending deletions due to rate limit")
                }
            #endif
            return
        }

        let pending = pendingDeletionIDs
        guard !pending.isEmpty else { return }

        let batch = Array(pending.prefix(currentGoogleAdaptiveBatchSize(cap: 5)))

        #if DEBUG
            debugLog("Processing \(batch.count)/\(pending.count) pending Google deletions")
        #endif

        for remoteKey in batch {
            await performDeletionAsync(remoteKey: remoteKey, token: token, localEventID: nil)
        }
    }

    func deleteEventFromGoogle(localEventID: UUID) {
        // 1. Check Auth & Look up Google ID
        guard googleStatus == .connected else {
            #if DEBUG
                debugLog("deleteEventFromGoogle: ignored (not connected)")
            #endif
            return
        }

        #if DEBUG
            debugLog(
                "deleteEventFromGoogle: requested localID=\(localEventID.uuidString) syncMapCount=\(syncMap.count) pendingDeletes=\(pendingDeletionIDs.count)"
            )
        #endif

        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await GoogleAuthService.shared.validAccessToken()
                await self.deleteEventFromGoogle(localEventID: localEventID, token: token)
            } catch {
                #if DEBUG
                    self.debugLog("Skipping Google Delete: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func deleteEventFromGoogle(localEventID: UUID, token: String) async {
        // Find Google remote key (fast path via cached reverse map)
        if let remoteKey = googleRemoteKey(forLocalID: localEventID.uuidString) {
            await MainActor.run {
                // Mark as deleted immediately to block sync resurrection
                var currentDeleted = self.deletedIDs
                if !currentDeleted.contains(remoteKey) {
                    currentDeleted.append(remoteKey)
                    self.deletedIDs = currentDeleted
                }
                // Queue deletion so we can retry until Google reflects the change
                self.enqueuePendingDeletion(remoteKey: remoteKey)
            }

            await performDeletionAsync(
                remoteKey: remoteKey, token: token, localEventID: localEventID)
            return
        }

        // If the syncMap is missing/stale, try to find the Google event by a private extended property.
        let localIDString = localEventID.uuidString
        #if DEBUG
            debugLog(
                "deleteEventFromGoogle: No syncMap mapping for local ID \(localIDString); attempting extendedProperty lookup"
            )
        #endif

        let remoteKeys = await lookupGoogleEventIDsByLocalID(
            localIDString: localIDString, token: token)
        guard !remoteKeys.isEmpty else {
            #if DEBUG
                debugLog(
                    "deleteEventFromGoogle: lookup returned 0 matches for local ID \(localIDString)"
                )
            #endif
            return
        }

        for remoteKey in remoteKeys {
            await MainActor.run {
                // Mark as deleted immediately to block sync resurrection
                var currentDeleted = self.deletedIDs
                if !currentDeleted.contains(remoteKey) {
                    currentDeleted.append(remoteKey)
                    self.deletedIDs = currentDeleted
                }

                self.enqueuePendingDeletion(remoteKey: remoteKey)
            }

            await performDeletionAsync(
                remoteKey: remoteKey, token: token, localEventID: localEventID)
        }
    }

    private func performDeletion(remoteKey: String, token: String, localEventID: UUID?) {
        Task { [weak self] in
            await self?.performDeletionAsync(
                remoteKey: remoteKey, token: token, localEventID: localEventID)
        }
    }

    private func performDeletionAsync(remoteKey: String, token: String, localEventID: UUID?) async {
        let parsed = parseGoogleRemoteKey(remoteKey)
        let calendarID = parsed.calendarID
        let eventID = parsed.eventID

        guard
            let encodedCalendarID = calendarID.addingPercentEncoding(
                withAllowedCharacters: Self.googleEventIDAllowedCharacters)
        else {
            #if DEBUG
                debugLog("performDeletion: failed to percent-encode calendarID=\(calendarID)")
            #endif
            return
        }

        // Ensure Google ID is URL-safe as a *single path segment*
        guard
            let encodedID = eventID.addingPercentEncoding(
                withAllowedCharacters: Self.googleEventIDAllowedCharacters)
        else {
            #if DEBUG
                debugLog("performDeletion: failed to percent-encode eventID=\(eventID)")
            #endif
            return
        }
        let urlString =
            "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events/\(encodedID)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        #if DEBUG
            if let localEventID {
                self.debugLog(
                    "Attempting to DELETE event on Google: \(remoteKey) (local=\(localEventID))")
            } else {
                self.debugLog("Attempting to DELETE event on Google (pending): \(remoteKey)")
            }
            self.debugLog("Google Delete URL: \(urlString)")
        #endif

        do {
            guard await awaitGoogleRequestSlot() else { return }
            let (data, response) = try await secureSession.data(for: request)
            guard let httpRes = response as? HTTPURLResponse else { return }

            #if DEBUG
                debugLog("Google Delete Response Code: \(httpRes.statusCode)")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    debugLog("Google Delete Response Body: \(body)")
                }
            #endif

            if httpRes.statusCode == 403 {
                let body = String(data: data, encoding: .utf8)
                if body?.contains("rateLimitExceeded") ?? false {
                    applyGoogleRateLimitBackoff(from: httpRes, responseBody: body)
                    return
                }
            }

            // 404 (not found) and 410 (gone) both mean "no longer exists"; treat as success.
            if (200...204).contains(httpRes.statusCode) || httpRes.statusCode == 404
                || httpRes.statusCode == 410
            {
                resetGoogleRateLimitBackoff()
                await MainActor.run {
                    var map = self.syncMap
                    map.removeValue(forKey: remoteKey)
                    self.setSyncMap(map)
                    self.removePendingDeletion(remoteKey: remoteKey)
                    #if DEBUG
                        self.debugLog(
                            "Google deletion confirmed; removed from map + pending queue: \(remoteKey)"
                        )
                    #endif
                }
            }
        } catch {
            #if DEBUG
                debugLog("Google Calendar Delete Error: \(error.localizedDescription)")
            #endif
            return
        }
    }

    private func lookupGoogleEventIDsByLocalID(
        localIDString: String,
        token: String
    ) async -> [String] {
        let calendarIDs = googleCalendarIDsForLookup()
        let filterValue = "\(Self.googleLocalIDExtendedPropertyKey)=\(localIDString)"

        var collected: [String] = []
        collected.reserveCapacity(8)

        for calendarID in calendarIDs {
            guard
                let encodedCalendarID = calendarID.addingPercentEncoding(
                    withAllowedCharacters: Self.googleEventIDAllowedCharacters)
            else { continue }

            var components = URLComponents(
                string:
                    "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
            )
            components?.queryItems = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "maxResults", value: "10"),
                URLQueryItem(name: "privateExtendedProperty", value: filterValue),
            ]

            guard let url = components?.url else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            #if DEBUG
                debugLog("lookupGoogleEventIDsByLocalID: \(url.absoluteString)")
            #endif

            do {
                guard await awaitGoogleRequestSlot() else { break }
                let (data, response) = try await secureSession.data(for: request)
                guard let http = response as? HTTPURLResponse,
                    (200...299).contains(http.statusCode)
                else {
                    #if DEBUG
                        if let http = response as? HTTPURLResponse {
                            debugLog(
                                "lookupGoogleEventIDsByLocalID failed status=\(http.statusCode)"
                            )
                        } else {
                            debugLog(
                                "lookupGoogleEventIDsByLocalID missing HTTP status")
                        }
                    #endif
                    continue
                }

                let decoded = try await decodeOffMain(GoogleCalendarListResponse.self, from: data)
                let remoteKeys = decoded.items.map {
                    makeGoogleRemoteKey(calendarID: calendarID, eventID: $0.id)
                }
                collected.append(contentsOf: remoteKeys)
            } catch {
                #if DEBUG
                    debugLog(
                        "lookupGoogleEventIDsByLocalID error: \(error.localizedDescription)"
                    )
                #endif
            }
        }

        return Array(Set(collected))
    }

    // MARK: - Outlook (Microsoft Graph) Integration

    func connectOutlook() {
        if outlookStatus == .connected { return }
        if outlookStatus == .connecting { outlookStatus = .disconnected }
        outlookStatus = .connecting
        OutlookAuthService.shared.signIn { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.outlookStatus = .connected
                    UserDefaults.standard.set(true, forKey: "OutlookConnected")
                    AppNotificationCenter.shared.post(
                        kind: .info, title: "Calendar Connected",
                        message: "Outlook Calendar sync enabled", autoDismissAfter: 4)
                    self.performOutlookInitialSync(showNotifications: true)
                    self.startOutlookBackgroundSync()
                case .failure(let error):
                    self.outlookStatus = .disconnected
                    UserDefaults.standard.set(false, forKey: "OutlookConnected")
                    if case OutlookAuthError.userCancelled = error { return }
                    AppNotificationCenter.shared.post(
                        kind: .error, title: "Connection Failed",
                        message: error.localizedDescription, autoDismissAfter: 5)
                }
            }
        }
    }

    func disconnectOutlook() {
        stopOutlookBackgroundSync()
        purgeOutlookEventsFromStore()
        OutlookAuthService.shared.signOut()
        outlookStatus = .disconnected
        UserDefaults.standard.set(false, forKey: "OutlookConnected")
        connectedCalendars.removeAll { $0.source == "Outlook" }
        AppNotificationCenter.shared.post(
            kind: .warning, title: "Calendar Disconnected",
            message: "Outlook Calendar sync disabled", autoDismissAfter: 4)
    }

    func resyncOutlookNow() {
        guard outlookStatus == .connected else { return }
        Task { [weak self] in await self?.syncOutlook(showNotifications: true) }
    }

    // nonisolated(unsafe): Task.cancel() is Sendable and safe to call from deinit.
    nonisolated(unsafe) private var outlookSyncTask: Task<Void, Never>?
    private var isOutlookSyncInFlight = false

    private func startOutlookBackgroundSync() {
        stopOutlookBackgroundSync()
        outlookSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let outlookConnected = await MainActor.run { self.outlookStatus == .connected }
                guard outlookConnected else { continue }
                await self.syncOutlook(showNotifications: false)
            }
        }
    }

    private func stopOutlookBackgroundSync() {
        outlookSyncTask?.cancel()
        outlookSyncTask = nil
    }

    private func performOutlookInitialSync(showNotifications: Bool) {
        Task { [weak self] in await self?.syncOutlook(showNotifications: showNotifications) }
    }

    private let outlookSyncMapKey = "OutlookCalendarSyncMap"
    private var _outlookSyncMap: [String: String] = [:]
    var outlookSyncMap: [String: String] {
        get { _outlookSyncMap }
        set {
            _outlookSyncMap = newValue
            UserDefaults.standard.set(newValue, forKey: outlookSyncMapKey)
        }
    }

    func syncOutlook(showNotifications: Bool) async {
        guard outlookStatus == .connected else { return }
        if isOutlookSyncInFlight { return }
        isOutlookSyncInFlight = true
        defer { Task { @MainActor [weak self] in self?.isOutlookSyncInFlight = false } }

        let notifID: UUID? =
            showNotifications
            ? await MainActor.run {
                AppNotificationCenter.shared.post(
                    kind: .progress, title: "Syncing Outlook",
                    message: "Connecting...", progress: 0.1)
            } : nil

        do {
            let token = try await OutlookAuthService.shared.validAccessToken()
            await fetchOutlookCalendarList(token: token)
            if let id = notifID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: id, message: "Importing events...", progress: 0.5)
                }
            }
            await fetchOutlookEvents(token: token, syncNotificationID: notifID)
        } catch {
            if let id = notifID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: id, title: "Sync Failed",
                        message: error.localizedDescription, kind: .error, autoDismissAfter: 5)
                }
            }
        }
    }

    private func fetchOutlookCalendarList(token: String) async {
        guard let url = URL(string: "https://graph.microsoft.com/v1.0/me/calendars?$top=50") else {
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await secureSession.data(for: req),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["value"] as? [[String: Any]]
        else { return }

        await MainActor.run {
            let calendars: [ConnectedCalendar] = items.compactMap { item in
                guard let id = item["id"] as? String, let name = item["name"] as? String else {
                    return nil
                }
                let colorHex = item["hexColor"] as? String ?? "#0078D4"
                return ConnectedCalendar(
                    id: "Outlook:\(id)", name: name, source: "Outlook",
                    color: Color(hex: colorHex), remoteID: id)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Single assignment fires objectWillChange once instead of twice.
            connectedCalendars = connectedCalendars.filter { $0.source != "Outlook" } + calendars

            let hasAnySelection = enabledCalendarIDs.contains { $0.hasPrefix("Outlook:") }
            if !hasAnySelection { ensureEnabled(calendars.map { $0.id }) }
        }
    }

    private func fetchOutlookEvents(token: String, syncNotificationID: UUID?) async {
        let calendarIDs = await MainActor.run {
            connectedCalendars.filter {
                $0.source == "Outlook" && enabledCalendarIDs.contains($0.id)
            }
            .compactMap { $0.remoteID }
        }
        guard !calendarIDs.isEmpty else {
            if let id = syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.complete(
                        id: id, title: "Outlook Synced", message: "No enabled calendars",
                        autoDismissAfter: 3)
                }
            }
            return
        }

        let now = Date()
        let cal = Calendar.current
        let tStart = (cal.date(byAdding: .year, value: -1, to: now) ?? now).ISO8601Format()
        let tEnd = (cal.date(byAdding: .year, value: 1, to: now) ?? now).ISO8601Format()

        for calID in calendarIDs {
            var pageURL: String? =
                "https://graph.microsoft.com/v1.0/me/calendars/\(calID)/calendarView?startDateTime=\(tStart)&endDateTime=\(tEnd)&$top=999&$select=id,subject,start,end,isAllDay,location,body,bodyPreview,webLink,onlineMeeting,onlineMeetingUrl"
            var allItems: [[String: Any]] = []
            while let urlStr = pageURL, let url = URL(string: urlStr) {
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                guard let (data, response) = try? await secureSession.data(for: req),
                    let http = response as? HTTPURLResponse
                else { break }
                if http.statusCode == 401 {
                    await MainActor.run { OutlookAuthService.shared.forceSignOut() }
                    return
                }
                guard (200...299).contains(http.statusCode),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let items = json["value"] as? [[String: Any]]
                else { break }
                allItems.append(contentsOf: items)
                pageURL = json["@odata.nextLink"] as? String
            }
            await syncOutlookEventsToStore(
                allItems, calendarID: calID, syncNotificationID: syncNotificationID)
        }

        if let id = syncNotificationID {
            await MainActor.run {
                AppNotificationCenter.shared.complete(
                    id: id, title: "Outlook Synced", message: "Calendar is up to date",
                    autoDismissAfter: 4)
            }
        }
    }


    private func purgeOutlookEventsFromStore() {
        let ids = outlookSyncMap.values.compactMap { UUID(uuidString: $0) }
        outlookSyncMap = [:]
        guard !ids.isEmpty else { return }
        CollegePersistence.shared.bulkDeleteCalendarEvents(withUUIDs: ids)
        notifyCalendarDidChangeMainActor()
    }

    // MARK: - iCloud CalDAV Integration

    private let iCloudUsernameKey = "icloud_caldav_username"
    private let iCloudPasswordKey = "icloud_caldav_password"
    private let iCloudKeychainService: String = {
        "\(Bundle.main.bundleIdentifier ?? "College").caldav.icloud"
    }()
    // nonisolated(unsafe): Task.cancel() is Sendable and safe to call from deinit.
    nonisolated(unsafe) private var iCloudSyncTask: Task<Void, Never>?
    private var isICloudSyncInFlight = false

    var iCloudUsername: String? { iCloudKeychainGet(iCloudUsernameKey) }

    func connectiCloud(username: String, password: String) {
        iCloudStatus = .connecting
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.validateiCloudCredentials(username: username, password: password)
                self.iCloudKeychainSet(self.iCloudUsernameKey, value: username)
                self.iCloudKeychainSet(self.iCloudPasswordKey, value: password)
                await MainActor.run {
                    self.iCloudStatus = .connected
                    UserDefaults.standard.set(true, forKey: "iCloudCalDAVConnected")
                    AppNotificationCenter.shared.post(
                        kind: .info, title: "iCloud Connected",
                        message: "iCloud Calendar sync enabled", autoDismissAfter: 4)
                }
                self.startiCloudBackgroundSync()
                Task { [weak self] in await self?.synciCloud(showNotifications: true) }
            } catch {
                await MainActor.run {
                    self.iCloudStatus = .disconnected
                    let msg =
                        (error as? CalDAVConnectionError)?.localizedDescription
                        ?? error.localizedDescription
                    AppNotificationCenter.shared.post(
                        kind: .error, title: "iCloud Connection Failed",
                        message: msg, autoDismissAfter: 5)
                }
            }
        }
    }

    func disconnectiCloud() {
        stopiCloudBackgroundSync()
        purgeiCloudEventsFromStore()
        iCloudKeychainDelete(iCloudUsernameKey)
        iCloudKeychainDelete(iCloudPasswordKey)
        UserDefaults.standard.removeObject(forKey: "iCloudCalDAVConnected")
        iCloudStatus = .disconnected
        connectedCalendars.removeAll { $0.source == "iCloudCalDAV" }
        AppNotificationCenter.shared.post(
            kind: .warning, title: "iCloud Disconnected",
            message: "iCloud Calendar sync disabled", autoDismissAfter: 4)
    }

    func resyncICloudNow() {
        guard iCloudStatus == .connected else { return }
        Task { [weak self] in await self?.synciCloud(showNotifications: true) }
    }

    private func startiCloudBackgroundSync() {
        stopiCloudBackgroundSync()
        iCloudSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let iCloudConnected = await MainActor.run { self.iCloudStatus == .connected }
                guard iCloudConnected else { continue }
                await self.synciCloud(showNotifications: false)
            }
        }
    }

    private func stopiCloudBackgroundSync() {
        iCloudSyncTask?.cancel()
        iCloudSyncTask = nil
    }

    private func validateiCloudCredentials(username: String, password: String) async throws {
        guard let url = URL(string: "https://caldav.icloud.com/.well-known/caldav") else {
            throw CalDAVConnectionError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&req, username: username, password: password)
        req.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVConnectionError.networkError
        }
        if http.statusCode == 401 { throw CalDAVConnectionError.authFailed }
    }

    func synciCloud(showNotifications: Bool) async {
        guard iCloudStatus == .connected else { return }
        if isICloudSyncInFlight { return }
        isICloudSyncInFlight = true
        defer { Task { @MainActor [weak self] in self?.isICloudSyncInFlight = false } }

        guard let username = iCloudKeychainGet(iCloudUsernameKey),
            let password = iCloudKeychainGet(iCloudPasswordKey)
        else {
            await MainActor.run { self.iCloudStatus = .disconnected }
            return
        }

        let notifID: UUID? =
            showNotifications
            ? await MainActor.run {
                AppNotificationCenter.shared.post(
                    kind: .progress, title: "Syncing iCloud", message: "Fetching calendars...",
                    progress: 0.2)
            } : nil

        do {
            let calendars = try await fetchiCloudCalendars(username: username, password: password)
            await MainActor.run {
                let connected = calendars.map { cal in
                    ConnectedCalendar(
                        id: "iCloudCalDAV:\(cal.path)", name: cal.displayName,
                        source: "iCloudCalDAV", color: Color(hex: cal.colorHex ?? "#007AFF"),
                        remoteID: cal.url.absoluteString)
                }
                // Single assignment fires objectWillChange once instead of twice.
                self.connectedCalendars = self.connectedCalendars.filter { $0.source != "iCloudCalDAV" } + connected
                let hasAny = self.enabledCalendarIDs.contains { $0.hasPrefix("iCloudCalDAV:") }
                if !hasAny { self.ensureEnabled(connected.map { $0.id }) }
            }
            if let id = notifID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: id, message: "Importing events...", progress: 0.6)
                }
            }

            let enabledURLs = await MainActor.run {
                connectedCalendars.filter {
                    $0.source == "iCloudCalDAV" && enabledCalendarIDs.contains($0.id)
                }
                .compactMap { $0.remoteID.flatMap { URL(string: $0) } }
            }
            let now = Date()
            let cal = Calendar.current
            let tMin = cal.date(byAdding: .year, value: -1, to: now) ?? now
            let tMax = cal.date(byAdding: .year, value: 1, to: now) ?? now

            for calURL in enabledURLs {
                let events = try await fetchiCloudEvents(
                    calendarURL: calURL, timeMin: tMin, timeMax: tMax,
                    username: username, password: password)
                await synciCloudEventsToStore(events, calendarURLString: calURL.absoluteString)
            }
            if let id = notifID {
                await MainActor.run {
                    AppNotificationCenter.shared.complete(
                        id: id, title: "iCloud Synced", message: "Calendar is up to date",
                        autoDismissAfter: 4)
                }
            }
        } catch {
            if let id = notifID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(
                        id: id, title: "Sync Failed", message: error.localizedDescription,
                        kind: .error, autoDismissAfter: 5)
                }
            }
        }
    }

    private struct iCloudCalendarInfo {
        let path: String
        let url: URL
        let displayName: String
        let colorHex: String?
    }

    private func fetchiCloudCalendars(username: String, password: String) async throws
        -> [iCloudCalendarInfo]
    {
        guard let wellKnown = URL(string: "https://caldav.icloud.com/.well-known/caldav") else {
            throw CalDAVConnectionError.invalidURL
        }
        var req = URLRequest(url: wellKnown)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&req, username: username, password: password)
        req.httpBody =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><D:propfind xmlns:D=\"DAV:\"><D:prop><D:current-user-principal/></D:prop></D:propfind>"
            .data(using: .utf8)
        let (d1, r1) = try await URLSession.shared.data(for: req)
        if let http = r1 as? HTTPURLResponse, http.statusCode == 401 {
            throw CalDAVConnectionError.authFailed
        }
        let principalHref = CalDAVMiniParser(data: d1).firstHrefValue(
            insideTag: "current-user-principal")
        let baseStr = r1.url?.host.map { "https://\($0)" } ?? "https://caldav.icloud.com"
        let principalStr = principalHref.map { $0.hasPrefix("http") ? $0 : baseStr + $0 } ?? baseStr

        guard let principalURL = URL(string: principalStr) else {
            throw CalDAVConnectionError.invalidURL
        }
        var req2 = URLRequest(url: principalURL)
        req2.httpMethod = "PROPFIND"
        req2.setValue("0", forHTTPHeaderField: "Depth")
        req2.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&req2, username: username, password: password)
        req2.httpBody =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><D:propfind xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:caldav\"><D:prop><C:calendar-home-set/></D:prop></D:propfind>"
            .data(using: .utf8)
        let (d2, _) = try await URLSession.shared.data(for: req2)
        let homeHref = CalDAVMiniParser(data: d2).firstHrefValue(insideTag: "calendar-home-set")
        let homeStr =
            homeHref.map { $0.hasPrefix("http") ? $0 : baseStr + $0 } ?? principalStr
            + "/calendars/"

        guard let homeURL = URL(string: homeStr) else { throw CalDAVConnectionError.invalidURL }
        var req3 = URLRequest(url: homeURL)
        req3.httpMethod = "PROPFIND"
        req3.setValue("1", forHTTPHeaderField: "Depth")
        req3.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&req3, username: username, password: password)
        req3.httpBody = """
            <?xml version="1.0" encoding="UTF-8"?>
            <D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:APPLE="http://apple.com/ns/ical/">
              <D:prop><D:displayname/><D:resourcetype/><APPLE:calendar-color/></D:prop>
            </D:propfind>
            """.data(using: .utf8)
        let (d3, _) = try await URLSession.shared.data(for: req3)
        return CalDAVMiniParser(data: d3).extractCalendars().map { info in
            let url =
                URL(string: info.href.hasPrefix("http") ? info.href : baseStr + info.href)
                ?? homeURL
            return iCloudCalendarInfo(
                path: info.href, url: url, displayName: info.displayName, colorHex: info.colorHex)
        }
    }

    private func fetchiCloudEvents(
        calendarURL: URL, timeMin: Date, timeMax: Date,
        username: String, password: String
    ) async throws -> [iCloudEventData] {
        var req = URLRequest(url: calendarURL)
        req.httpMethod = "REPORT"
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        addCalDAVAuth(&req, username: username, password: password)
        let tMin = formatCalDAVTimestamp(timeMin)
        let tMax = formatCalDAVTimestamp(timeMax)
        req.httpBody = """
            <?xml version="1.0" encoding="UTF-8"?>
            <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
              <D:prop><D:getetag/><C:calendar-data/></D:prop>
              <C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VEVENT">
                <C:time-range start="\(tMin)" end="\(tMax)"/>
              </C:comp-filter></C:comp-filter></C:filter>
            </C:calendar-query>
            """.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw CalDAVConnectionError.authFailed
        }
        return CalDAVMiniParser(data: data).extractEvents()
    }

    private func formatCalDAVTimestamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private let iCloudCalDAVSyncMapKey = "iCloudCalDAVSyncMap"
    private var _iCloudSyncMap: [String: String] = [:]
    var iCloudSyncMap: [String: String] {
        get { _iCloudSyncMap }
        set {
            _iCloudSyncMap = newValue
            UserDefaults.standard.set(newValue, forKey: iCloudCalDAVSyncMapKey)
        }
    }

    private func addCalDAVAuth(_ req: inout URLRequest, username: String, password: String) {
        if let data = "\(username):\(password)".data(using: .utf8) {
            req.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
    }

    private func iCloudKeychainSet(_ key: String, value: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: iCloudKeychainService,
            kSecAttrAccount as String: key,
        ]
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            == errSecItemNotFound
        {
            var a = q
            a[kSecValueData as String] = data
            SecItemAdd(a as CFDictionary, nil)
        }
    }

    private func iCloudKeychainGet(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: iCloudKeychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
            let d = ref as? Data
        else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func iCloudKeychainDelete(_ key: String) {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: iCloudKeychainService,
                kSecAttrAccount as String: key,
            ] as CFDictionary)
    }

}

// MARK: - Google JSON Structs

struct GoogleCalendarListResponse: Codable {
    let items: [GoogleCalendarEventItem]
    let nextPageToken: String?
    let nextSyncToken: String?
}

struct GoogleCalendarEventItem: Codable {
    let id: String
    let summary: String?
    let location: String?
    let description: String?
    let start: GoogleCalendarDate
    let end: GoogleCalendarDate
    // Enrichment fields
    let status: String?  // "confirmed" | "tentative" | "cancelled"
    let colorId: String?
    let recurrence: [String]?
    let attendees: [GoogleAttendee]?
    let conferenceData: GoogleConferenceData?
    let reminders: GoogleReminders?
}

struct GoogleAttendee: Codable {
    let email: String?
    let displayName: String?
    let responseStatus: String?  // "accepted" | "declined" | "tentative" | "needsAction"
    let organizer: Bool?
    let `self`: Bool?
}

struct GoogleConferenceData: Codable {
    let entryPoints: [GoogleConferenceEntryPoint]?
    let conferenceSolution: GoogleConferenceSolution?
}

struct GoogleConferenceEntryPoint: Codable {
    let entryPointType: String?  // "video" | "phone" | "sip" | "more"
    let uri: String?
    let label: String?
}

struct GoogleConferenceSolution: Codable {
    let name: String?
}

struct GoogleReminders: Codable {
    let useDefault: Bool?
    let overrides: [GoogleReminderOverride]?
}

struct GoogleReminderOverride: Codable {
    let method: String?  // "popup" | "email"
    let minutes: Int?
}

private struct GoogleCreatedEventResponse: Codable {
    let id: String
}

struct GoogleCalendarDate: Codable {
    let dateTime: String?
    let date: String?
}

// https://developers.google.com/calendar/api/v3/reference/calendarList/list
private struct GoogleCalendarListListResponse: Codable {
    let items: [GoogleCalendarListEntry]
}

private struct GoogleCalendarListEntry: Codable {
    let id: String
    let summary: String?
    let primary: Bool?
    let selected: Bool?
    let hidden: Bool?
    let backgroundColor: String?
}

struct GoogleEventUpload: Encodable {
    let summary: String
    let location: String?
    let description: String?
    let start: GoogleCalendarDate
    let end: GoogleCalendarDate
    let extendedProperties: GoogleExtendedProperties?
    let recurrence: [String]?
    let conferenceDataVersion: Int?

    enum CodingKeys: String, CodingKey {
        case summary, location, description, start, end, extendedProperties, recurrence
        case conferenceDataVersion
    }
}

struct GoogleExtendedProperties: Encodable {
    let privateProperties: [String: String]?

    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }
}

// MARK: - Google Attendee JSON helpers

enum GoogleAttendeeHelper {
    /// Encodes an array of GoogleAttendee to a compact JSON string for storage.
    static func encode(_ attendees: [GoogleAttendee]) -> String? {
        guard !attendees.isEmpty else { return nil }
        return try? String(data: JSONEncoder().encode(attendees), encoding: .utf8)
    }

    /// Decodes a JSON string back to [GoogleAttendee].
    static func decode(_ json: String) -> [GoogleAttendee] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GoogleAttendee].self, from: data)) ?? []
    }

    /// Returns the best conference join URL from a GoogleConferenceData, preferring video.
    static func primaryJoinURL(from conf: GoogleConferenceData?) -> String? {
        guard let conf else { return nil }
        let points = conf.entryPoints ?? []
        // Prefer video entry points
        if let video = points.first(where: { $0.entryPointType == "video" }) {
            return video.uri
        }
        return points.first?.uri
    }

    /// Returns the earliest popup reminder in minutes (nil if none).
    static func earliestPopupMinutes(from reminders: GoogleReminders?) -> Int? {
        guard let overrides = reminders?.overrides else { return nil }
        return
            overrides
            .filter { $0.method == "popup" }
            .compactMap { $0.minutes }
            .min()
    }

    /// Extracts first RRULE string from a recurrence array.
    static func rrule(from recurrence: [String]?) -> String? {
        recurrence?.first(where: { $0.hasPrefix("RRULE:") })
            .map { String($0.dropFirst("RRULE:".count)) }
    }
}

// MARK: - CalDAV Connection Errors

enum CalDAVConnectionError: LocalizedError {
    case invalidURL, authFailed, networkError
    case parseError(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid iCloud CalDAV URL."
        case .authFailed:
            return "Authentication failed. Check your Apple ID and App-Specific Password."
        case .networkError: return "Network error connecting to iCloud."
        case .parseError(let m): return "Parse error: \(m)"
        }
    }
}

// MARK: - iCloud Event Data

struct iCloudEventData: Sendable {
    let uid: String
    let summary: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

// MARK: - CalDAV Minimal XML Parser

private class CalDAVMiniParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var text = ""
    private var responses: [Row] = []
    private var current: Row?
    private var inResp = false

    struct Row {
        var href = ""
        var displayName = ""
        var colorHex: String?
        var isCalendar = false
        var calendarData = ""
        var etag = ""
    }
    struct CalDAVCalendarEntry {
        let href: String
        let displayName: String
        let colorHex: String?
    }

    init(data: Data) { self.data = data }

    func firstHrefValue(insideTag tag: String) -> String? {
        class X: NSObject, XMLParserDelegate {
            let t: String
            var v: String?
            var in_ = false
            var d = 0
            var b = ""
            init(_ t: String) { self.t = t }
            func parser(
                _ p: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]
            ) {
                let l = e.components(separatedBy: ":").last ?? e
                if l == t {
                    in_ = true
                    d += 1
                    b = ""
                } else if in_ {
                    d += 1
                }
            }
            func parser(_ p: XMLParser, foundCharacters s: String) { if in_ { b += s } }
            func parser(
                _ p: XMLParser, didEndElement e: String, namespaceURI: String?,
                qualifiedName: String?
            ) {
                guard in_ else { return }
                d -= 1
                if d == 0 {
                    in_ = false
                    let t2 = b.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t2.isEmpty { v = t2 }
                }
            }
        }
        let x = X(tag)
        let p = XMLParser(data: data)
        p.delegate = x
        p.parse()
        return x.v
    }

    func extractCalendars() -> [CalDAVCalendarEntry] {
        parseAll()
        return responses.filter { $0.isCalendar && !$0.href.isEmpty }.map {
            CalDAVCalendarEntry(
                href: $0.href,
                displayName: $0.displayName.isEmpty ? $0.href : $0.displayName,
                colorHex: $0.colorHex)
        }
    }

    func extractEvents() -> [iCloudEventData] {
        parseAll()
        return responses.compactMap { r in
            r.calendarData.isEmpty ? nil : ICalMiniParser.parseVEvent(r.calendarData)
        }
    }

    private func parseAll() {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(
        _ p: XMLParser, didStartElement e: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        let l = e.components(separatedBy: ":").last ?? e
        text = ""
        if l == "response" {
            inResp = true
            current = Row()
        }
        if l == "calendar" { current?.isCalendar = true }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(
        _ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?
    ) {
        let l = e.components(separatedBy: ":").last ?? e
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inResp {
            switch l {
            case "href": if current?.href.isEmpty == true { current?.href = t }
            case "displayname": current?.displayName = t
            case "calendar-color": current?.colorHex = t
            case "calendar-data": current?.calendarData = t
            case "getetag": current?.etag = t.replacingOccurrences(of: "\"", with: "")
            default: break
            }
        }
        if l == "response", let r = current, !r.href.isEmpty {
            responses.append(r)
            inResp = false
            current = nil
        }
        text = ""
    }
}

// MARK: - iCalendar Minimal Parser

private enum ICalMiniParser {
    static func parseVEvent(_ ical: String) -> iCloudEventData? {
        let lines =
            ical
            .replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(
                of: "\r\n\t", with: ""
            )
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: .newlines)

        var uid: String?
        var summary: String?
        var dtstart: String?
        var dtend: String?
        var startTZ: String?
        var endTZ: String?
        var location: String?
        var notes: String?
        var isAllDay = false
        var inEvent = false

        for line in lines {
            if line.uppercased() == "BEGIN:VEVENT" {
                inEvent = true
                continue
            }
            if line.uppercased() == "END:VEVENT" { break }
            guard inEvent else { continue }
            let (prop, params, value) = split(line)
            switch prop.uppercased() {
            case "UID": uid = value
            case "SUMMARY": summary = unescape(value)
            case "DTSTART":
                dtstart = value
                if params.uppercased().contains("VALUE=DATE") { isAllDay = true }
                startTZ = tz(params)
            case "DTEND", "DUE":
                dtend = value
                if params.uppercased().contains("VALUE=DATE") { isAllDay = true }
                endTZ = tz(params)
            case "LOCATION": location = unescape(value)
            case "DESCRIPTION": notes = unescape(value)
            default: break
            }
        }
        guard let uid, let rawStart = dtstart else { return nil }
        let start =
            isAllDay
            ? parseDate(rawStart) ?? Date() : parseDateTime(rawStart, tz: startTZ) ?? Date()
        let end =
            isAllDay
            ? parseDate(dtend ?? rawStart) ?? start.addingTimeInterval(86400)
            : parseDateTime(dtend ?? rawStart, tz: endTZ) ?? start.addingTimeInterval(3600)
        return iCloudEventData(
            uid: uid, summary: summary ?? "(No Title)", startDate: start, endDate: end,
            isAllDay: isAllDay,
            location: location?.isEmpty == false ? location : nil,
            notes: notes?.isEmpty == false ? notes : nil)
    }

    private static func split(_ line: String) -> (String, String, String) {
        guard let ci = line.firstIndex(of: ":") else { return (line, "", "") }
        let key = String(line[..<ci])
        let val = String(line[line.index(after: ci)...])
        if let si = key.firstIndex(of: ";") {
            return (String(key[..<si]), String(key[key.index(after: si)...]), val)
        }
        return (key, "", val)
    }
    private static func tz(_ params: String) -> String? {
        for part in params.components(separatedBy: ";") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2, kv[0].uppercased() == "TZID" { return kv[1] }
        }
        return nil
    }
    private static let _parseDateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"; f.timeZone = .current; return f
    }()
    private static let _parseDateTimeFmtUTC: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static let _parseDateTimeFmtLocal: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"; f.timeZone = .current; return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        return _parseDateFmt.date(from: String(s.prefix(8)))
    }
    private static func parseDateTime(_ s: String, tz: String?) -> Date? {
        if s.hasSuffix("Z") {
            return _parseDateTimeFmtUTC.date(from: s)
        }
        if let tzid = tz, let zone = TimeZone(identifier: tzid) {
            // Non-UTC explicit timezone: set once, parse, reset — this path is rare
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            f.timeZone = zone
            return f.date(from: s)
        }
        return _parseDateTimeFmtLocal.date(from: s)
    }
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Outlook Auth Service

enum OutlookAuthError: Error {
    case missingConfiguration, invalidURL, userCancelled, unableToStartSession
    case authenticationFailed(Error)
    case invalidResponse, tokenSerializationError
}

class OutlookAuthService: NSObject, ObservableObject {
    nonisolated(unsafe) static let shared = OutlookAuthService()
    @Published var isAuthenticated = false
    private var currentAuthSession: ASWebAuthenticationSession?
    private lazy var secureSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()
    private struct Cfg { let clientID, redirectURI, callbackScheme: String }
    private func cfg() throws -> Cfg {
        guard
            let cid = (Bundle.main.object(forInfoDictionaryKey: "MICROSOFT_CLIENT_ID") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty,
            let ruri =
                (Bundle.main.object(forInfoDictionaryKey: "MICROSOFT_REDIRECT_URI") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !ruri.isEmpty
        else { throw OutlookAuthError.missingConfiguration }
        let scheme =
            URL(string: ruri)?.scheme ?? "msauth.\(Bundle.main.bundleIdentifier ?? "college")"
        return Cfg(clientID: cid, redirectURI: ruri, callbackScheme: scheme)
    }
    private func form(_ p: [String: String]) -> Data? {
        var c = URLComponents()
        c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.percentEncodedQuery?.data(using: .utf8)
    }
    private let kAT = "microsoft_access_token", kRT = "microsoft_refresh_token",
        kExp = "microsoft_token_expiry"
    private let kcSvc: String = { "\(Bundle.main.bundleIdentifier ?? "College").microsoft.oauth" }()
    private var cAT: String?
    private var cRT: String?
    private var cExp: TimeInterval?
    private let scopes = "https://graph.microsoft.com/Calendars.ReadWrite offline_access User.Read"

    override init() {
        super.init()
        restoreSession()
    }

    private func restoreSession() {
        guard kcGet(kAT) != nil, kcGet(kRT) != nil else { return }
        isAuthenticated = true
        if let s = kcGet(kExp), let t = TimeInterval(s),
            Date().addingTimeInterval(60).timeIntervalSince1970 >= t
        {
            refreshToken { _ in }
        }
    }

    @MainActor func signOut() {
        revokeAsync()
        forceSignOut()
    }
    @MainActor func forceSignOut() {
        kcDel(kAT)
        kcDel(kRT)
        kcDel(kExp)
        cAT = nil
        cRT = nil
        cExp = nil
        isAuthenticated = false
    }
    nonisolated private func revokeAsync() {
        guard let at = OutlookAuthService.shared.cAT,
            let url = URL(string: "https://graph.microsoft.com/v1.0/me/revokeSignInSessions")
        else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(at)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()
    }

    @MainActor func signIn(completion: @Sendable @escaping (Result<Void, Error>) -> Void) {
        let c: Cfg
        do { c = try cfg() } catch {
            completion(.failure(error))
            return
        }
        let state = UUID().uuidString
        let cv = codeVerifier()
        guard let cc = codeChallenge(cv) else {
            completion(.failure(OutlookAuthError.invalidURL))
            return
        }
        guard
            var comps = URLComponents(
                string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
        else {
            completion(.failure(OutlookAuthError.invalidURL))
            return
        }
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: c.clientID),
            URLQueryItem(name: "redirect_uri", value: c.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: cc),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = comps.url else {
            completion(.failure(OutlookAuthError.invalidURL))
            return
        }
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: c.callbackScheme)
        { [weak self] url, err in
            guard let self else { return }
            defer { self.currentAuthSession = nil }
            if let err = err {
                let code = (err as NSError).code
                completion(
                    .failure(
                        code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                            ? OutlookAuthError.userCancelled
                            : OutlookAuthError.authenticationFailed(err)))
                return
            }
            guard let url,
                let qi = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems,
                let code = qi.first(where: { $0.name == "code" })?.value,
                let rs = qi.first(where: { $0.name == "state" })?.value, rs == state
            else {
                completion(.failure(OutlookAuthError.invalidResponse))
                return
            }
            self.exchangeCode(code: code, cv: cv, c: c, completion: completion)
        }
        session.presentationContextProvider = self
        currentAuthSession = session
        guard session.start() else {
            currentAuthSession = nil
            completion(.failure(OutlookAuthError.unableToStartSession))
            return
        }
    }

    private func exchangeCode(
        code: String, cv: String, c: Cfg,
        completion: @Sendable @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")
        else {
            completion(.failure(OutlookAuthError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "client_id": c.clientID, "redirect_uri": c.redirectURI,
            "code": code, "grant_type": "authorization_code",
            "code_verifier": cv, "scope": scopes,
        ])
        secureSession.dataTask(with: req) { data, _, error in
            if let e = error {
                Task { @MainActor in completion(.failure(e)) }
                return
            }
            guard let data else {
                Task { @MainActor in completion(.failure(OutlookAuthError.invalidResponse)) }
                return
            }
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let at = j["access_token"] as? String
            {
                Task { @MainActor in
                    OutlookAuthService.shared.kcSet(OutlookAuthService.shared.kAT, v: at)
                    OutlookAuthService.shared.cAT = at
                    if let rt = j["refresh_token"] as? String {
                        OutlookAuthService.shared.kcSet(OutlookAuthService.shared.kRT, v: rt)
                        OutlookAuthService.shared.cRT = rt
                    }
                    if let ei = j["expires_in"] as? TimeInterval {
                        let exp = Date().addingTimeInterval(ei)
                        OutlookAuthService.shared.kcSet(
                            OutlookAuthService.shared.kExp, v: String(exp.timeIntervalSince1970))
                        OutlookAuthService.shared.cExp = exp.timeIntervalSince1970
                    }
                    OutlookAuthService.shared.isAuthenticated = true
                    completion(.success(()))
                }
            } else {
                Task { @MainActor in completion(.failure(OutlookAuthError.tokenSerializationError))
                }
            }
        }.resume()
    }

    func getValidToken(completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        let exp: TimeInterval? =
            cExp
            ?? {
                if let s = kcGet(kExp), let t = TimeInterval(s) {
                    cExp = t
                    return t
                }
                return nil
            }()
        if let exp, Date().addingTimeInterval(60).timeIntervalSince1970 < exp,
            let tok = cAT ?? kcGet(kAT)
        {
            cAT = tok
            completion(.success(tok))
            return
        }
        refreshToken(completion: completion)
    }

    private func refreshToken(completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        guard let rt = cRT ?? kcGet(kRT) else {
            completion(.failure(OutlookAuthError.missingConfiguration))
            return
        }
        cRT = rt
        let c: Cfg
        do { c = try cfg() } catch {
            completion(.failure(error))
            return
        }
        guard let url = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")
        else {
            completion(.failure(OutlookAuthError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form([
            "client_id": c.clientID, "refresh_token": rt,
            "grant_type": "refresh_token", "scope": scopes,
        ])
        secureSession.dataTask(with: req) { data, _, error in
            if let e = error {
                Task { @MainActor in completion(.failure(e)) }
                return
            }
            guard let data else {
                Task { @MainActor in completion(.failure(OutlookAuthError.invalidResponse)) }
                return
            }
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let at = j["access_token"] as? String
            {
                Task { @MainActor in
                    OutlookAuthService.shared.kcSet(OutlookAuthService.shared.kAT, v: at)
                    OutlookAuthService.shared.cAT = at
                    if let ei = j["expires_in"] as? TimeInterval {
                        let exp = Date().addingTimeInterval(ei)
                        OutlookAuthService.shared.kcSet(
                            OutlookAuthService.shared.kExp, v: String(exp.timeIntervalSince1970))
                        OutlookAuthService.shared.cExp = exp.timeIntervalSince1970
                    }
                    completion(.success(at))
                }
            } else {
                if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let ec = j["error"] as? String,
                    ec == "invalid_grant" || ec == "interaction_required"
                {
                    Task { @MainActor in
                        OutlookAuthService.shared.forceSignOut()
                        completion(.failure(OutlookAuthError.missingConfiguration))
                    }
                } else {
                    Task { @MainActor in
                        completion(.failure(OutlookAuthError.tokenSerializationError))
                    }
                }
            }
        }.resume()
    }

    private func codeVerifier() -> String {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return Data(b).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
    }
    private func codeChallenge(_ v: String) -> String? {
        guard let d = v.data(using: .utf8) else { return nil }
        return Data(SHA256.hash(data: d)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
    }

    private func kcSet(_ k: String, v: String) {
        let data = Data(v.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcSvc, kSecAttrAccount as String: k,
        ]
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            == errSecItemNotFound
        {
            var a = q
            a[kSecValueData as String] = data
            SecItemAdd(a as CFDictionary, nil)
        }
    }
    private func kcGet(_ k: String) -> String? {
        if k == kAT, let v = cAT { return v }
        if k == kRT, let v = cRT { return v }
        if k == kExp, let t = cExp { return String(t) }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcSvc, kSecAttrAccount as String: k,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess, let d = ref as? Data
        else { return nil }
        let val = String(data: d, encoding: .utf8)
        if k == kAT { cAT = val }
        if k == kRT { cRT = val }
        if k == kExp, let val, let t = TimeInterval(val) { cExp = t }
        return val
    }
    private func kcDel(_ k: String) {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: kcSvc, kSecAttrAccount as String: k,
            ] as CFDictionary)
    }

    func validAccessToken() async throws -> String {
        try await withCheckedThrowingContinuation { cont in getValidToken { cont.resume(with: $0) }
        }
    }
}

extension OutlookAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared
            .windows.first ?? ASPresentationAnchor()
    }
}
