// CalendarEventGuestsCodec.swift
// Feature: Calendar
// Purpose: Calendar module — GuestRecord.
// Data: CollegePersistence / repositories when applicable.

import Contacts
import Foundation

/// Encodes/decodes guest lists for `CalendarStoredEventEntity.attendeesJSON` (Phase 3b).
public enum CalendarEventGuestsCodec {
    public struct GuestRecord: Codable, Sendable {
        public var name: String
        public var email: String?
        /// Google/Apple RSVP: accepted, declined, tentative, needsAction
        public var responseStatus: String?

        public init(name: String, email: String?, responseStatus: String? = nil) {
            self.name = name
            self.email = email
            self.responseStatus = responseStatus
        }
    }

    public static func encode(records: [GuestRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(records) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func encode(contacts: [CNContact]) -> String? {
        let records: [GuestRecord] = contacts.map { contact in
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.givenName
            let email = contact.emailAddresses.first.map { $0.value as String }
            return GuestRecord(name: name, email: email)
        }
        return encode(records: records)
    }

    /// Decodes guest JSON stored as GuestRecord array or legacy GoogleAttendee payloads.
    public static func decodeFlexible(_ json: String?) -> [GuestRecord] {
        let direct = decode(json)
        if !direct.isEmpty { return direct }
        guard let json,
              let data = json.data(using: .utf8),
              let google = try? JSONDecoder().decode([GoogleAttendeePayload].self, from: data)
        else { return [] }
        return google.compactMap { payload in
            let email = payload.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !email.isEmpty else { return nil }
            let name = (payload.displayName ?? email).trimmingCharacters(in: .whitespacesAndNewlines)
            return GuestRecord(name: name, email: email, responseStatus: payload.responseStatus)
        }
    }

    private struct GoogleAttendeePayload: Codable {
        let email: String?
        let displayName: String?
        let responseStatus: String?
    }

    public static func decode(_ json: String?) -> [GuestRecord] {
        guard let json,
              let data = json.data(using: .utf8),
              let records = try? JSONDecoder().decode([GuestRecord].self, from: data)
        else { return [] }
        return records
    }
}
