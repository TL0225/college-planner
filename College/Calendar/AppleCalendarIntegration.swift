import Foundation
import EventKit
import SwiftUI

/// EventKit-backed integration for Apple Calendar (macOS).
///
/// This keeps sync state in UserDefaults to avoid Core Data migrations.
/// Mapping strategy:
/// - Primary key: `EKEvent.calendarItemExternalIdentifier` when available, else `eventIdentifier`
/// - Stored in a map: externalID -> local UUID string
/// - For events created by this app, we also set `EKEvent.url` to `college://event/<uuid>`.
enum AppleCalendarIntegration {
    // MARK: - UserDefaults keys

    private static let appleConnectedKey = "AppleCalendarConnected"
    private static let appleEnabledCalendarsKey = "AppleCalendarEnabledCalendars"
    private static let applePrimaryCalendarIDKey = "AppleCalendarPrimaryCalendarID"

    private static let appleSyncMapKey = "AppleCalendarSyncMap" // externalID -> localUUIDString
    private static let appleDeletedIDsKey = "AppleCalendarDeletedExternalIDs" // tombstones to avoid resurrection

    // MARK: - URL tagging

    static let appEventURLScheme = "college"

    static func makeAppEventURL(localID: UUID) -> URL? {
        URL(string: "\(appEventURLScheme)://event/\(localID.uuidString)")
    }

    static func extractLocalID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == appEventURLScheme else { return nil }
        guard url.host?.lowercased() == "event" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: path)
    }

    // MARK: - Persistence helpers

    static var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: appleConnectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: appleConnectedKey) }
    }

    static var enabledCalendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: appleEnabledCalendarsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: appleEnabledCalendarsKey) }
    }

    static var primaryCalendarIdentifier: String? {
        get { UserDefaults.standard.string(forKey: applePrimaryCalendarIDKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: applePrimaryCalendarIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: applePrimaryCalendarIDKey)
            }
        }
    }

    static var syncMap: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: appleSyncMapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: appleSyncMapKey) }
    }

    static var deletedExternalIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: appleDeletedIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: appleDeletedIDsKey) }
    }

    // MARK: - EventKit helpers

    static func bestExternalID(for event: EKEvent) -> String? {
        // `calendarItemExternalIdentifier` is generally more stable across edits than `eventIdentifier`.
        if let id = event.calendarItemExternalIdentifier, !id.isEmpty { return id }
        if let id = event.eventIdentifier, !id.isEmpty { return id }
        return nil
    }

    static func ensurePrimaryCalendar(in store: EKEventStore) -> EKCalendar? {
        return ensureCalendar(named: "College", in: store, storeIdentifier: true)
    }

    /// Finds the calendar with the given `name` in the same writable source as the
    /// primary "College" calendar, creating it if it does not yet exist.
    /// Unlike `ensurePrimaryCalendar`, the identifier is **not** persisted — it is
    /// resolved by title each time because course codes are stable across launches.
    static func ensureCalendar(named name: String, in store: EKEventStore) -> EKCalendar? {
        return ensureCalendar(named: name, in: store, storeIdentifier: false)
    }

    // MARK: - Private implementation

    private static func ensureCalendar(
        named name: String,
        in store: EKEventStore,
        storeIdentifier: Bool
    ) -> EKCalendar? {
        // Only use the persisted identifier shortcut when managing the primary calendar.
        if storeIdentifier,
           let id = primaryCalendarIdentifier,
           let existing = store.calendar(withIdentifier: id),
           existing.allowsContentModifications {
            return existing
        }

        // Prefer an iCloud/CalDAV source when available; fall back to local.
        let writableSources = store.sources.filter { source in
            // Many sources can create calendars; local sources typically can as well.
            source.sourceType != .subscribed
        }

        guard let source = writableSources.first else { return nil }

        let calendarName = name
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarName && $0.source == source }) {
            if storeIdentifier { primaryCalendarIdentifier = existing.calendarIdentifier }
            return existing
        }

        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendarName
        cal.source = source
        do {
            try store.saveCalendar(cal, commit: true)
            if storeIdentifier { primaryCalendarIdentifier = cal.calendarIdentifier }
            return cal
        } catch {
            return nil
        }
    }
}

