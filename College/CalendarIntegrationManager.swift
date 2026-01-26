import Foundation
import SwiftUI
import Combine
import CoreData

enum CalendarConnectionStatus: String {
    case disconnected = "CONNECT"
    case connecting = "CONNECTING..."
    case connected = "SYNCED"
}

struct ConnectedCalendar: Identifiable, Hashable {
    let id: String
    let name: String
    let source: String // "Apple" or "Google"
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
    
    @Published var connectedCalendars: [ConnectedCalendar] = [
        ConnectedCalendar(id: "Apple:Home", name: "Home", source: "Apple", color: .red, remoteID: nil),
        ConnectedCalendar(id: "Apple:School", name: "School", source: "Apple", color: .yellow, remoteID: nil)
    ]

    @Published var enabledCalendarIDs: Set<String>

    private let enabledCalendarsKey = "EnabledCalendars"
    private let knownGoogleCalendarsKey = "KnownGoogleCalendars"
    private let persistedGoogleCalendarsKey = "PersistedGoogleCalendars"
    private let primaryGoogleCalendarIDKey = "PrimaryGoogleCalendarID"
    private var primaryGoogleCalendarID: String? = nil
    
    private var syncTimer: Timer?
    private var isSyncInFlight: Bool = false
    private var queuedSyncRequest: Bool = false
    
    // Fast lookup to avoid O(n) scans of syncMap during rendering.
    // Key: local UUID lowercased -> remoteKey (calendarID||eventID)
    private var googleRemoteKeyByLocalIDLower: [String: String] = [:]
    
    // Store mapping of GoogleEventID -> LocalUUIDString to prevent duplicates
    private let syncMapKey = "GoogleCalendarSyncMap"
    private let deletedIDsKey = "GoogleCalendarDeletedIDs"
    private let pendingDeletionsKey = "GoogleCalendarPendingDeletions"
    private let pendingUpsertsKey = "GoogleCalendarPendingUpserts"

    private static let googleRemoteKeySeparator = "||"

    private let googleRateLimitUntilKey = "GoogleCalendarRateLimitUntil"
    private let googleRateLimitBackoffSecondsKey = "GoogleCalendarRateLimitBackoffSeconds"

    private static let googleEventIDAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    private static let googleLocalIDExtendedPropertyKey = "college_local_id"
    
    private var syncMap: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: syncMapKey) as? [String: String] ?? [:]
        }
        set {
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

    private func setSyncMap(_ map: [String: String]) {
        syncMap = map
        rebuildGoogleReverseMap(from: map)
    }

    private func googleRemoteKey(forLocalID localID: String) -> String? {
        let key = localID.lowercased()
        if let v = googleRemoteKeyByLocalIDLower[key] { return v }
        // If we missed an update (e.g. after app relaunch), rebuild once on-demand.
        let m = syncMap
        rebuildGoogleReverseMap(from: m)
        return googleRemoteKeyByLocalIDLower[key]
    }

    private var deletedIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: deletedIDsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: deletedIDsKey)
        }
    }

    private var pendingDeletionIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: pendingDeletionsKey)
        }
    }

    // Local UUID strings that need to be (re)exported to Google.
    private var pendingUpsertLocalIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: pendingUpsertsKey) ?? []
        }
        set {
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
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: googleRateLimitUntilKey)
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
    
    init() {
        let persistedEnabled = UserDefaults.standard.stringArray(forKey: enabledCalendarsKey) ?? []
        let defaultEnabled: Set<String> = ["Apple:Home", "Apple:School"]
        self.enabledCalendarIDs = Set(persistedEnabled.isEmpty ? Array(defaultEnabled) : persistedEnabled)

        // Restore cached Google calendar list (so the picker isn't empty while syncing).
        // Safe because we only surface these when Google is currently marked connected.
        if UserDefaults.standard.bool(forKey: "GoogleConnected") {
            self.primaryGoogleCalendarID = UserDefaults.standard.string(forKey: primaryGoogleCalendarIDKey)
            restorePersistedGoogleCalendars()
        }

        // Build the in-memory reverse lookup cache for fast UI filtering.
        rebuildGoogleReverseMap(from: syncMap)

        if googleStatus == .connected {
            #if DEBUG
            GoogleDebugLog.ensureFileExists()
            #endif
            performInitialSync(showNotifications: false)
            startBackgroundSync()
        }
    }

    func sourceCalendarColor(for event: CalendarEventEntity) -> Color? {
        guard let localID = event.id?.uuidString else { return nil }

        // 1) Google events: derive calendar from syncMap remote key.
        if let remoteKey = googleRemoteKey(forLocalID: localID) {
            let parsed = parseGoogleRemoteKey(remoteKey)
            let toggleID = toggleIDForGoogleCalendarID(parsed.calendarID)
            return connectedCalendars.first(where: { $0.id == toggleID })?.color
        }

        // 2) Local (Apple) events
        let appleID: String = {
            if event.course != nil || event.semester != nil { return "Apple:School" }
            return "Apple:Home"
        }()

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
        guard let data = UserDefaults.standard.data(forKey: persistedGoogleCalendarsKey) else { return }

        guard let decoded = try? JSONDecoder().decode([PersistedGoogleCalendar].self, from: data) else { return }

        let googleCalendars: [ConnectedCalendar] = decoded
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

        connectedCalendars.removeAll(where: { $0.source == "Google" })
        connectedCalendars.append(contentsOf: googleCalendars)
    }

    func isCalendarEnabled(_ calendar: ConnectedCalendar) -> Bool {
        enabledCalendarIDs.contains(calendar.id)
    }

    func toggleCalendarEnabled(_ calendar: ConnectedCalendar) {
        if enabledCalendarIDs.contains(calendar.id) {
            enabledCalendarIDs.remove(calendar.id)
        } else {
            enabledCalendarIDs.insert(calendar.id)
        }
        persistEnabledCalendars()
    }

    private func persistEnabledCalendars() {
        UserDefaults.standard.set(Array(enabledCalendarIDs), forKey: enabledCalendarsKey)
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

    private func makeGoogleRemoteKey(calendarID: String, eventID: String) -> String {
        "\(calendarID)\(Self.googleRemoteKeySeparator)\(eventID)"
    }

    private func parseGoogleRemoteKey(_ key: String) -> (calendarID: String, eventID: String) {
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
    func googleRecurringSeriesKey(for event: CalendarEventEntity) -> String? {
        guard let localID = event.id?.uuidString else { return nil }
        guard let remoteKey = googleRemoteKey(forLocalID: localID) else { return nil }
        let parsed = parseGoogleRemoteKey(remoteKey)
        guard let baseEventID = googleRecurringSeriesID(fromGoogleEventID: parsed.eventID) else { return nil }
        return makeGoogleRemoteKey(calendarID: parsed.calendarID, eventID: baseEventID)
    }

    private func defaultGoogleCalendarID() -> String {
        if let primaryGoogleCalendarID {
            return primaryGoogleCalendarID
        }

        let enabledGoogleIDs = connectedCalendars
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

    func shouldDisplayEvent(_ event: CalendarEventEntity) -> Bool {
        guard let localID = event.id?.uuidString else { return true }

        // 1) Google events
        if let remoteKey = googleRemoteKey(forLocalID: localID) {
            let parsed = parseGoogleRemoteKey(remoteKey)
            let toggleID = toggleIDForGoogleCalendarID(parsed.calendarID)

            // If we haven't fetched calendarList yet, don't hide events unexpectedly.
            if !connectedCalendars.contains(where: { $0.id == toggleID }) {
                return true
            }
            return enabledCalendarIDs.contains(toggleID)
        }

        // 2) Local (Apple) events
        let appleID: String = {
            // Treat course/semester-linked items as "School".
            if event.course != nil || event.semester != nil {
                return "Apple:School"
            }
            return "Apple:Home"
        }()

        return enabledCalendarIDs.contains(appleID)
    }

    #if DEBUG
    private enum DebugFileLogger {
        private static let queue = DispatchQueue(label: "College.GoogleCalendar.DebugFileLogger")

        private static var fileURL: URL? {
            GoogleDebugLog.fileURL()
        }

        static func log(_ message: String) {
            queue.async {
                guard let url = fileURL else { return }

                GoogleDebugLog.ensureFileExists()

                let timestamp = ISO8601DateFormatter().string(from: Date())
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

    nonisolated private func debugLog(_ message: String) {
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
                    self.debugLog("Google OAuth sign-in SUCCESS; marking connected and starting initial sync")
                    #endif
                    self.googleStatus = .connected
                    UserDefaults.standard.set(true, forKey: "GoogleConnected")
                    self.primaryGoogleCalendarID = UserDefaults.standard.string(forKey: self.primaryGoogleCalendarIDKey)
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
        purgeGoogleCalendarEventsFromCoreDataAndClearState()

        GoogleAuthService.shared.signOut()
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

    private struct LocalEventExportSnapshot {
        let localIDString: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
    }

    private func exportAllLocalEventsToGoogle(token: String) {
        guard googleStatus == .connected else { return }

        let context = CoreDataManager.shared.viewContext
        context.perform { [weak self] in
            guard let self else { return }

            let req = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
            req.returnsObjectsAsFaults = false

            let events: [CalendarEventEntity]
            do {
                events = try context.fetch(req)
            } catch {
                #if DEBUG
                self.debugLog("exportAllLocalEventsToGoogle(): fetch failed: \(error)")
                #endif
                return
            }

            let snapshots: [LocalEventExportSnapshot] = events.compactMap { event in
                guard let id = event.id else { return nil }
                return LocalEventExportSnapshot(
                    localIDString: id.uuidString,
                    title: event.title ?? "New Event",
                    start: event.startDate ?? Date(),
                    end: event.endDate ?? Date().addingTimeInterval(3600),
                    isAllDay: event.allDay,
                    location: event.location,
                    notes: event.notes
                )
            }

            #if DEBUG
            self.debugLog("exportAllLocalEventsToGoogle(): exporting \(snapshots.count) events")
            #endif

            for snap in snapshots {
                self.enqueuePendingUpsert(localID: snap.localIDString)
                self.performExport(
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
    }

    private func isGoogleRateLimitedNow() -> Bool {
        guard let until = googleRateLimitUntil else { return false }
        return until > Date()
    }

    private func applyGoogleRateLimitBackoff(from response: HTTPURLResponse?, responseBody: String?) {
        // Prefer server hint if present.
        var retryAfterSeconds: Double?
        if let value = response?.value(forHTTPHeaderField: "Retry-After"),
           let s = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            retryAfterSeconds = s
        }

        let now = Date()
        let previous = googleRateLimitBackoffSeconds
        let next = max(15, min(600, previous > 0 ? previous * 2 : 30))
        let chosen = retryAfterSeconds ?? next

        googleRateLimitBackoffSeconds = next
        googleRateLimitUntil = now.addingTimeInterval(chosen)

        #if DEBUG
        debugLog("Google rate limit hit; backing off for \(Int(chosen))s (nextBackoff=\(Int(next))s)")
        #endif
        
        let retryMessage = retryAfterSeconds != nil ? "Retrying in \(Int(chosen))s" : "Retrying in \(Int(chosen))s"
        DispatchQueue.main.async {
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
    }

    private func purgeGoogleCalendarEventsFromCoreDataAndClearState() {
        let mapSnapshot = syncMap
        let localIDs = mapSnapshot.values.compactMap { UUID(uuidString: $0) }

        #if DEBUG
        debugLog("disconnectGoogle(): purging \(localIDs.count) local events belonging to Google calendar")
        #endif

        func fingerprint(title: String?, start: Date?, end: Date?, allDay: Bool, location: String?, notes: String?) -> String {
            let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let loc = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let n = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Minute-level resolution avoids tiny second differences.
            let s = Int((start ?? .distantPast).timeIntervalSince1970 / 60.0)
            let e = Int((end ?? .distantPast).timeIntervalSince1970 / 60.0)
            return "\(t)|\(allDay ? 1 : 0)|\(s)|\(e)|\(loc)|\(n)"
        }

        // Even if some Google-imported events were duplicated without syncMap entries,
        // we can still delete them by matching against the fingerprints of mapped Google events.

        let context = CoreDataManager.shared.viewContext
        context.perform {
            var idsToDelete = Set<UUID>()
            idsToDelete.formUnion(localIDs)

            // 1) Build fingerprint set from mapped Google events.
            var googleFingerprints = Set<String>()
            if !localIDs.isEmpty {
                let mappedReq = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
                mappedReq.predicate = NSPredicate(format: "id IN %@", localIDs)
                mappedReq.returnsObjectsAsFaults = false
                if let mapped = try? context.fetch(mappedReq) {
                    for event in mapped {
                        googleFingerprints.insert(
                            fingerprint(
                                title: event.title,
                                start: event.startDate,
                                end: event.endDate,
                                allDay: event.allDay,
                                location: event.location,
                                notes: event.notes
                            )
                        )
                    }
                }
            }

            // 2) Delete any orphan/duplicate personal events matching those fingerprints.
            if !googleFingerprints.isEmpty {
                let personalReq = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
                personalReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "course == nil"),
                    NSPredicate(format: "semester == nil")
                ])
                personalReq.returnsObjectsAsFaults = false

                if let personals = try? context.fetch(personalReq) {
                    for event in personals {
                        let fp = fingerprint(
                            title: event.title,
                            start: event.startDate,
                            end: event.endDate,
                            allDay: event.allDay,
                            location: event.location,
                            notes: event.notes
                        )
                        if googleFingerprints.contains(fp), let id = event.id {
                            idsToDelete.insert(id)
                        }
                    }
                }
            }

            // Clear sync state so UI/reconnect starts from a clean slate.
            DispatchQueue.main.async {
                self.setSyncMap([:])
                self.deletedIDs = []
                self.pendingDeletionIDs = []
                self.pendingUpsertLocalIDs = []
            }

            guard !idsToDelete.isEmpty else {
                CoreDataManager.shared.notifyCalendarDidChange()
                return
            }

            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "CalendarEventEntity")
            fetch.predicate = NSPredicate(format: "id IN %@", Array(idsToDelete))

            let request = NSBatchDeleteRequest(fetchRequest: fetch)
            request.resultType = .resultTypeObjectIDs

            do {
                let result = try context.execute(request) as? NSBatchDeleteResult
                let deletedObjectIDs = result?.result as? [NSManagedObjectID] ?? []
                if !deletedObjectIDs.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
                        into: [context]
                    )
                }

                CoreDataManager.shared.notifyCalendarDidChange()

                #if DEBUG
                self.debugLog("disconnectGoogle(): purge complete (deleted=\(deletedObjectIDs.count))")
                #endif
            } catch {
                #if DEBUG
                self.debugLog("disconnectGoogle(): purge FAILED: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Background Sync
    
    private func startBackgroundSync() {
        stopBackgroundSync() // Ensure no duplicates
        // Sync every 1 minute (60 seconds)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, self.googleStatus == .connected else { return }
            #if DEBUG
            self.debugLog("Background Sync Timer fired.")
            #endif
            // Background syncs run silently (no notifications) to avoid noise
            // Only manual syncs via resyncGoogleNow() show notifications
            Task { [weak self] in
                await self?.syncGoogle(showNotifications: false)
            }
        }
    }
    
    private func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func performInitialSync(showNotifications: Bool = false) {
        Task { [weak self] in
            await self?.syncGoogle(showNotifications: showNotifications)
        }
    }
    
    // MARK: - Google API Fetch
    private func syncGoogle(showNotifications: Bool) async {
        // Ensure we never overlap sync work.
        let syncNotificationID: UUID?
        let shouldRun: Bool

        (syncNotificationID, shouldRun) = await MainActor.run {
            if self.isSyncInFlight {
                self.queuedSyncRequest = true
                return (nil, false)
            }
            self.isSyncInFlight = true

            let id: UUID? = showNotifications ? AppNotificationCenter.shared.post(
                kind: .progress,
                title: "Syncing Calendar",
                message: "Connecting to Google Calendar...",
                progress: 0.1
            ) : nil
            return (id, true)
        }

        guard shouldRun else { return }

        guard googleStatus == .connected else {
            await MainActor.run { self.isSyncInFlight = false }
            return
        }

        do {
            try Task.checkCancellation()
            let token = try await GoogleAuthService.shared.validAccessToken()
            try Task.checkCancellation()

            if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(id: syncNotificationID, message: "Fetching calendar list...", progress: 0.3)
                }
            }

            await processPendingGoogleDeletions(token: token)
            await processPendingGoogleUpserts(token: token)
            try Task.checkCancellation()

            await fetchGoogleCalendarList(token: token)
            try Task.checkCancellation()

            if let syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(id: syncNotificationID, message: "Importing events...", progress: 0.6)
                }
            }

            await fetchRealGoogleEvents(token: token, syncNotificationID: syncNotificationID)
        } catch is CancellationError {
            // Best-effort: treat cancellation as a silent stop (no error toast).
        } catch {
            #if DEBUG
            debugLog("syncGoogle(): token error: \(error.localizedDescription)")
            #endif
            if let syncNotificationID {
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
        let google = connectedCalendars
            .filter { $0.source == "Google" && enabledCalendarIDs.contains($0.id) }
            .compactMap { $0.remoteID }

        return google
    }

    private func googleCalendarIDsForLookup() -> [String] {
        let google = connectedCalendars
            .filter { $0.source == "Google" }
            .compactMap { $0.remoteID }

        return google.isEmpty ? ["primary"] : google
    }

    private func decodeOffMain<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        }.value
    }

    private func fetchGoogleCalendarList(token: String) async {
        guard googleStatus == .connected else { return }
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        #if DEBUG
        debugLog("Fetching Google calendarList: \(url.absoluteString)")
        #endif

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard (200...299).contains(http.statusCode) else {
                #if DEBUG
                debugLog("Google calendarList failed status=\(http.statusCode)")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    debugLog("Google calendarList body: \(body)")
                }
                #endif
                return
            }

            let decoded = try await decodeOffMain(GoogleCalendarListListResponse.self, from: data)

            await MainActor.run {
                let visibleItems = decoded.items.filter { ($0.hidden ?? false) == false }

                let googleCalendars: [ConnectedCalendar] = visibleItems
                    .map { item in
                        let color: Color = {
                            if let hex = item.backgroundColor { return Color(hex: hex) }
                            return .blue
                        }()
                        let summary = (item.summary ?? "Google Calendar").trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = summary.isEmpty ? item.id : summary
                        return ConnectedCalendar(
                            id: "Google:\(item.id)",
                            name: name,
                            source: "Google",
                            color: color,
                            remoteID: item.id
                        )
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                let primaryID = decoded.items.first(where: { $0.primary ?? false })?.id
                self.primaryGoogleCalendarID = primaryID
                UserDefaults.standard.set(primaryID, forKey: self.primaryGoogleCalendarIDKey)

                self.connectedCalendars.removeAll(where: { $0.source == "Google" })
                self.connectedCalendars.append(contentsOf: googleCalendars)

                // Persist the last known list so UI can render immediately after relaunch/resync.
                let persisted = visibleItems.map { item in
                    let summary = (item.summary ?? "Google Calendar").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = summary.isEmpty ? item.id : summary
                    return PersistedGoogleCalendar(id: item.id, name: name, backgroundColorHex: item.backgroundColor)
                }
                self.persistGoogleCalendars(persisted)

                // Do not override user calendar selections on each sync.
                // Auto-enable only on first connect OR for newly discovered calendars.
                let known = Set(UserDefaults.standard.stringArray(forKey: self.knownGoogleCalendarsKey) ?? [])
                let discovered = Set(visibleItems.map { $0.id })
                let newlyDiscovered = discovered.subtracting(known)
                UserDefaults.standard.set(Array(discovered), forKey: self.knownGoogleCalendarsKey)

                let hasAnyGoogleSelection = self.enabledCalendarIDs.contains(where: { $0.hasPrefix("Google:") })

                if !hasAnyGoogleSelection {
                    let selectedIDs = decoded.items
                        .filter { ($0.selected ?? false) || ($0.primary ?? false) }
                        .map { "Google:\($0.id)" }

                    let enableIDs = selectedIDs.isEmpty ? googleCalendars.map { $0.id } : selectedIDs
                    self.ensureEnabled(enableIDs)
                } else if !newlyDiscovered.isEmpty {
                    let autoEnableIDs = decoded.items
                        .filter { newlyDiscovered.contains($0.id) && (($0.selected ?? false) || ($0.primary ?? false)) }
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
        // Google expects RFC3339 timestamp with optional offset
        // Minimal: ISO8601DateFormatter
        let isoFn = ISO8601DateFormatter()
        let timeMin = isoFn.string(from: oneYearAgo)

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

        await withTaskGroup(of: Void.self) { group in
            for calendarID in calendarIDs {
                group.addTask { [weak self] in
                    await self?.fetchGoogleEvents(
                        calendarID: calendarID,
                        timeMin: timeMin,
                        token: token,
                        syncNotificationID: syncNotificationID
                    )
                }
            }
        }
    }

    private func fetchGoogleEvents(
        calendarID: String,
        timeMin: String,
        token: String,
        syncNotificationID: UUID? = nil
    ) async {
        guard let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) else {
            #if DEBUG
            debugLog("fetchGoogleEvents: failed to encode calendarID=\(calendarID)")
            #endif
            return
        }

        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events?singleEvents=true&orderBy=startTime&timeMin=\(timeMin)") else {
            return
        }

        #if DEBUG
        debugLog("Fetching Google Events from: \(url)")
        #endif

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8)
                if httpResponse.statusCode == 403, (body?.contains("rateLimitExceeded") ?? false) {
                    applyGoogleRateLimitBackoff(from: httpResponse, responseBody: body)
                }
                let errorMessage = httpResponse.statusCode == 403 ? "Rate limit exceeded" : "HTTP \(httpResponse.statusCode)"
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

            let listResponse = try await decodeOffMain(GoogleCalendarListResponse.self, from: data)

            #if DEBUG
            debugLog("Fetched \(listResponse.items.count) events from Google calendarID=\(calendarID)")
            #endif

            if let syncNotificationID = syncNotificationID {
                await MainActor.run {
                    AppNotificationCenter.shared.update(id: syncNotificationID, message: "Syncing changes...", progress: 0.9)
                }
            }

            await syncGoogleEventsToCoreDataAsync(
                listResponse.items,
                calendarID: calendarID,
                syncNotificationID: syncNotificationID
            )
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
    }

    private func syncGoogleEventsToCoreDataAsync(
        _ items: [GoogleCalendarEventItem],
        calendarID: String,
        syncNotificationID: UUID? = nil
    ) async {
        await withCheckedContinuation { continuation in
            syncGoogleEventsToCoreData(items, calendarID: calendarID, syncNotificationID: syncNotificationID) {
                continuation.resume()
            }
        }
    }
    
    private func syncGoogleEventsToCoreData(
        _ items: [GoogleCalendarEventItem],
        calendarID: String,
        syncNotificationID: UUID? = nil,
        completion: @escaping () -> Void
    ) {
        let coreData = CoreDataManager.shared
        let container = coreData.container
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var mapUpdates: [String: String] = [:]
        var mapRemovals: [String] = []
        
        let isoFormatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let currentMap = self.syncMap
        let mappedLocalIDsLower = Set(currentMap.values.map { $0.lowercased() })
        let deletedTombstones = Set(self.deletedIDs)

        context.perform { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion() }
                return
            }
            var newCount = 0

            func findReusableUnmappedLocalEvent(
                title: String,
                isAllDay: Bool,
                start: Date,
                end: Date
            ) -> CalendarEventEntity? {
                // Conservative de-dupe: only reuse events that look like Google imports (no course/semester)
                // and match start/end/allDay/title closely.
                let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
                request.fetchLimit = 8
                request.returnsObjectsAsFaults = false
                let titlePredicate = NSPredicate(format: "title ==[cd] %@", title)
                let allDayPredicate = NSPredicate(format: "allDay == %@", NSNumber(value: isAllDay))

                let startLower = start.addingTimeInterval(-1)
                let startUpper = start.addingTimeInterval(1)
                let endLower = end.addingTimeInterval(-1)
                let endUpper = end.addingTimeInterval(1)

                let startPredicate = NSPredicate(format: "startDate >= %@ AND startDate <= %@", startLower as NSDate, startUpper as NSDate)
                let endPredicate = NSPredicate(format: "endDate >= %@ AND endDate <= %@", endLower as NSDate, endUpper as NSDate)

                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [titlePredicate, allDayPredicate, startPredicate, endPredicate])

                guard let matches = try? context.fetch(request), !matches.isEmpty else { return nil }
                for candidate in matches {
                    guard candidate.course == nil, candidate.semester == nil else { continue }
                    guard let cid = candidate.id?.uuidString.lowercased(), !mappedLocalIDsLower.contains(cid) else { continue }
                    return candidate
                }
                return nil
            }

            func fetchLocalEvent(uuid: UUID) -> CalendarEventEntity? {
                let req = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
                req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                req.fetchLimit = 1
                return try? context.fetch(req).first
            }

            for item in items {
                let remoteKey = self.makeGoogleRemoteKey(calendarID: calendarID, eventID: item.id)
                let legacyKey = item.id

                // If this event was locally deleted, skip it to prevent "resurrection".
                // Back-compat: older builds stored tombstones as eventID-only for the primary calendar.
                if deletedTombstones.contains(remoteKey) || (calendarID == "primary" && deletedTombstones.contains(legacyKey)) {
                    continue
                }

                // Determine Start / End
                var startDate: Date?
                var endDate: Date?
                var isAllDay = false
                
                if let dt = item.start.dateTime {
                    startDate = isoFormatter.date(from: dt)
                } else if let d = item.start.date {
                    startDate = dateFormatter.date(from: d)
                    isAllDay = true
                }
                
                if let dt = item.end.dateTime {
                    endDate = isoFormatter.date(from: dt)
                } else if let d = item.end.date {
                    endDate = dateFormatter.date(from: d)
                }
                
                // Fallback for parser differences if needed (Google ISO often has offsets)
                // ISO8601DateFormatter handles offsets well.
                
                guard let finalStart = startDate, let finalEnd = endDate else { continue }
                
                let title = item.summary ?? "(No Title)"
                let location = item.location
                let notes = item.description
                
                // Check if already imported
                var eventExists = false
                let mappedLocalIDString = currentMap[remoteKey] ?? (calendarID == "primary" ? currentMap[legacyKey] : nil)
                if let localIDString = mappedLocalIDString,
                   let uuid = UUID(uuidString: localIDString),
                   let localEvent = fetchLocalEvent(uuid: uuid) {
                    eventExists = true

                    // Migrate legacy map key to composite remote key.
                    if currentMap[remoteKey] == nil, calendarID == "primary", currentMap[legacyKey] != nil {
                        mapUpdates[remoteKey] = localIDString
                        mapRemovals.append(legacyKey)
                    }
                    
                    // Update existing event from Google Data
                    // We only update fields that Google "owns" or shares (Title, Time, Location, Notes)
                    // We preserve app-specific links like Semester/Course if possible.
                    
                    if localEvent.title != title ||
                       localEvent.startDate != finalStart ||
                       localEvent.endDate != finalEnd ||
                       localEvent.allDay != isAllDay ||
                       localEvent.location != location ||
                       localEvent.notes != notes {
                        
                        localEvent.title = title
                        localEvent.startDate = finalStart
                        localEvent.endDate = finalEnd
                        localEvent.allDay = isAllDay
                        localEvent.location = location
                        localEvent.notes = notes
                        
                        // Mark as updated so View updates?
                        // Core Data context save (at end of loop via CoreDataManager) triggers publishing.
                    }
                }
                
                if !eventExists {
                    if let reusable = findReusableUnmappedLocalEvent(
                        title: title,
                        isAllDay: isAllDay,
                        start: finalStart,
                        end: finalEnd
                    ),
                    let existingID = reusable.id?.uuidString {
                        // Re-attach mapping instead of creating duplicates.
                        mapUpdates[remoteKey] = existingID
                        // Keep the local copy up-to-date.
                        reusable.location = location
                        reusable.notes = notes
                        reusable.lastUpdated = Date()
                    } else {
                        // Create new
                        let newEvent = CalendarEventEntity(context: context)
                        newEvent.id = UUID()
                        newEvent.title = title
                        newEvent.startDate = finalStart
                        newEvent.endDate = finalEnd
                        newEvent.allDay = isAllDay
                        newEvent.notes = notes
                        newEvent.location = location
                        newEvent.createdAt = Date()
                        newEvent.lastUpdated = Date()
                        newEvent.semester = nil
                        newEvent.course = nil

                        if let newID = newEvent.id {
                            mapUpdates[remoteKey] = newID.uuidString
                            newCount += 1
                        }
                    }
                }
            }
            
            #if DEBUG
            self.debugLog("Synced \(newCount) new events to Core Data.")
            #endif
            
            // Persist content updates (background context)
            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                self.debugLog("syncGoogleEventsToCoreData: background save FAILED: \(error)")
                #endif
            }
            
            // Merge map updates (avoid overwriting concurrent calendar sync results)
            let finalNewCount = newCount
            DispatchQueue.main.async {
                var map = self.syncMap
                for key in mapRemovals {
                    map.removeValue(forKey: key)
                }
                for (k, v) in mapUpdates {
                    map[k] = v
                }
                self.setSyncMap(map)
                
                // Show completion notification
                if let syncNotificationID = syncNotificationID {
                    if finalNewCount > 0 {
                        AppNotificationCenter.shared.complete(
                            id: syncNotificationID,
                            title: "Calendar Synced",
                            message: "\(finalNewCount) new event\(finalNewCount == 1 ? "" : "s") synced from Google Calendar",
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
                completion()
            }
        }
    }
    
    private func fetchLocalEvent(uuid: UUID) -> CalendarEventEntity? {
        let context = CoreDataManager.shared.viewContext
        var result: CalendarEventEntity?
        context.performAndWait {
            let req = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            req.fetchLimit = 1
            result = try? context.fetch(req).first
        }
        return result
    }

    // MARK: - Google API Export (Two-Way Sync)
    
    func exportEventToGoogle(_ event: CalendarEventEntity) {
        // 1. Check Auth
        guard googleStatus == .connected else { return }
        
        // Extract data on current thread (MainActor usually) to avoid MO invalidation
        let localIDString = event.id?.uuidString ?? ""
        let title = event.title ?? "New Event"
        let notes = event.notes
        let location = event.location
        let start = event.startDate ?? Date()
        let end = event.endDate ?? Date().addingTimeInterval(3600)
        let isAllDay = event.allDay

        if !localIDString.isEmpty {
            enqueuePendingUpsert(localID: localIDString)
        }

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
                    token: token
                )
                if success, !localIDString.isEmpty {
                    await MainActor.run { self.removePendingUpsert(localID: localIDString) }
                }
            } catch {
                #if DEBUG
                self.debugLog("Skipping Google Export (no token): \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func enqueuePendingUpsert(localID: String) {
        var pending = pendingUpsertLocalIDs
        guard !pending.contains(localID) else { return }
        pending.append(localID)
        pendingUpsertLocalIDs = pending
    }

    private func removePendingUpsert(localID: String) {
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
        let batch = Array(pending.prefix(10))

        #if DEBUG
        debugLog("Processing \(batch.count)/\(pending.count) pending Google upserts")
        #endif

        for localIDString in batch {
            guard let uuid = UUID(uuidString: localIDString) else {
                await MainActor.run { removePendingUpsert(localID: localIDString) }
                continue
            }

            guard let event = fetchLocalEvent(uuid: uuid) else {
                // Event no longer exists locally; drop it from the queue.
                await MainActor.run { removePendingUpsert(localID: localIDString) }
                continue
            }

            // Extract and export without re-enqueueing.
            let title = event.title ?? "New Event"
            let notes = event.notes
            let location = event.location
            let start = event.startDate ?? Date()
            let end = event.endDate ?? Date().addingTimeInterval(3600)
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

    private func performExport(
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

    private func performExportAsync(
        localIDString: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        token: String
    ) async -> Bool {
        // 2. Prepare Data
        let isoFormatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let googleStart: GoogleCalendarDate
        let googleEnd: GoogleCalendarDate
        
        if isAllDay {
            let sDate = dateFormatter.string(from: start)
            let eDate = dateFormatter.string(from: end)
            googleStart = GoogleCalendarDate(dateTime: nil, date: sDate)
            googleEnd = GoogleCalendarDate(dateTime: nil, date: eDate)
        } else {
            let sDate = isoFormatter.string(from: start)
            let eDate = isoFormatter.string(from: end)
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
            return self.defaultGoogleCalendarID()
        }()
        
        // 4. Create Request
        let encodedCalendarID = targetCalendarID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) ?? targetCalendarID
        let baseURL = "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
        var url: URL?
        var httpMethod: String
        
        if let remoteKey = existingRemoteKey {
            let gID = self.parseGoogleRemoteKey(remoteKey).eventID
            // UPDATE
            let encodedID = gID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) ?? gID
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
                ? GoogleExtendedProperties(privateProperties: [Self.googleLocalIDExtendedPropertyKey: localIDString])
                : nil
        )
        
        guard let requestUrl = url else { return }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            print("Failed to encode event: \(error)")
            return false
        }
        
        // 5. Execute
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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

                if statusCode == 403, (responseBody?.contains("rateLimitExceeded") ?? false) {
                    applyGoogleRateLimitBackoff(from: http, responseBody: responseBody)
                }

                // Some Google-managed event types reject updates; don't keep retrying forever.
                if statusCode == 400, (responseBody?.contains("eventTypeRestriction") ?? false) {
                    await MainActor.run { removePendingUpsert(localID: localIDString) }
                    #if DEBUG
                    debugLog("Dropping pending upsert due to eventTypeRestriction localID=\(localIDString)")
                    #endif
                }

                return false
            }

            resetGoogleRateLimitBackoff()

            // If created (POST), we get back the ID. Update SyncMap.
            if httpMethod == "POST" {
                if let created = try? await decodeOffMain(GoogleCreatedEventResponse.self, from: data) {
                    await MainActor.run {
                        self.updateSyncMap(calendarID: targetCalendarID, eventID: created.id, localID: localIDString)
                    }
                    #if DEBUG
                    debugLog("Google Export success (POST). GoogleID=\(created.id) localID=\(localIDString)")
                    #endif
                } else {
                    #if DEBUG
                    debugLog("Google Export success (POST) but could not decode response; localID=\(localIDString)")
                    #endif
                }
            } else {
                #if DEBUG
                debugLog("Google Export success (\(httpMethod)). localID=\(localIDString) status=\(statusCode)")
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

        let batch = Array(pending.prefix(10))

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
        debugLog("deleteEventFromGoogle: requested localID=\(localEventID.uuidString) syncMapCount=\(syncMap.count) pendingDeletes=\(pendingDeletionIDs.count)")
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

            await performDeletionAsync(remoteKey: remoteKey, token: token, localEventID: localEventID)
            return
        }

        // If the syncMap is missing/stale, try to find the Google event by a private extended property.
        let localIDString = localEventID.uuidString
        #if DEBUG
        debugLog("deleteEventFromGoogle: No syncMap mapping for local ID \(localIDString); attempting extendedProperty lookup")
        #endif

        let remoteKeys = await lookupGoogleEventIDsByLocalID(localIDString: localIDString, token: token)
        guard !remoteKeys.isEmpty else {
            #if DEBUG
            debugLog("deleteEventFromGoogle: lookup returned 0 matches for local ID \(localIDString)")
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

            await performDeletionAsync(remoteKey: remoteKey, token: token, localEventID: localEventID)
        }
    }

    private func performDeletion(remoteKey: String, token: String, localEventID: UUID?) {
        Task { [weak self] in
            await self?.performDeletionAsync(remoteKey: remoteKey, token: token, localEventID: localEventID)
        }
    }

    private func performDeletionAsync(remoteKey: String, token: String, localEventID: UUID?) async {
        let parsed = parseGoogleRemoteKey(remoteKey)
        let calendarID = parsed.calendarID
        let eventID = parsed.eventID

        guard let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) else {
            #if DEBUG
            debugLog("performDeletion: failed to percent-encode calendarID=\(calendarID)")
            #endif
            return
        }

        // Ensure Google ID is URL-safe as a *single path segment*
        guard let encodedID = eventID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) else {
            #if DEBUG
            debugLog("performDeletion: failed to percent-encode eventID=\(eventID)")
            #endif
            return
        }
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events/\(encodedID)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        #if DEBUG
        if let localEventID {
            self.debugLog("Attempting to DELETE event on Google: \(remoteKey) (local=\(localEventID))")
        } else {
            self.debugLog("Attempting to DELETE event on Google (pending): \(remoteKey)")
        }
        self.debugLog("Google Delete URL: \(urlString)")
        #endif
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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
            if (200...204).contains(httpRes.statusCode) || httpRes.statusCode == 404 || httpRes.statusCode == 410 {
                resetGoogleRateLimitBackoff()
                await MainActor.run {
                    var map = self.syncMap
                    map.removeValue(forKey: remoteKey)
                    self.setSyncMap(map)
                    self.removePendingDeletion(remoteKey: remoteKey)
                    #if DEBUG
                    self.debugLog("Google deletion confirmed; removed from map + pending queue: \(remoteKey)")
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

        await withTaskGroup(of: [String].self) { group in
            for calendarID in calendarIDs {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    guard let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: Self.googleEventIDAllowedCharacters) else { return [] }

                    var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")
                    components?.queryItems = [
                        URLQueryItem(name: "singleEvents", value: "true"),
                        URLQueryItem(name: "maxResults", value: "10"),
                        URLQueryItem(name: "privateExtendedProperty", value: filterValue)
                    ]

                    guard let url = components?.url else { return [] }

                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    #if DEBUG
                    self.debugLog("lookupGoogleEventIDsByLocalID: \(url.absoluteString)")
                    #endif

                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            #if DEBUG
                            if let http = response as? HTTPURLResponse {
                                self.debugLog("lookupGoogleEventIDsByLocalID failed status=\(http.statusCode)")
                            } else {
                                self.debugLog("lookupGoogleEventIDsByLocalID missing HTTP status")
                            }
                            #endif
                            return []
                        }

                        let decoded = try await self.decodeOffMain(GoogleCalendarListResponse.self, from: data)
                        return decoded.items.map { self.makeGoogleRemoteKey(calendarID: calendarID, eventID: $0.id) }
                    } catch {
                        #if DEBUG
                        self.debugLog("lookupGoogleEventIDsByLocalID error: \(error.localizedDescription)")
                        #endif
                        return []
                    }
                }
            }

            for await remoteKeys in group {
                collected.append(contentsOf: remoteKeys)
            }
        }

        return Array(Set(collected))
    }

}

// MARK: - Google JSON Structs

struct GoogleCalendarListResponse: Codable {
    let items: [GoogleCalendarEventItem]
}

struct GoogleCalendarEventItem: Codable {
    let id: String
    let summary: String?
    let location: String?
    let description: String?
    let start: GoogleCalendarDate
    let end: GoogleCalendarDate
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
}

struct GoogleExtendedProperties: Encodable {
    let privateProperties: [String: String]?

    enum CodingKeys: String, CodingKey {
        case privateProperties = "private"
    }
}

