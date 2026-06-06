// CalendarEventGuestsCodec.swift
// Feature: Calendar
// Purpose: Calendar module — GuestRecord.
// Data: CollegePersistence / repositories when applicable.

import Contacts
import Foundation

/// Encodes/decodes guest lists for `CalendarStoredEventEntity.attendeesJSON` (Phase 3b).
enum CalendarEventGuestsCodec {
    struct GuestRecord: Codable, Sendable {
        var name: String
        var email: String?
    }

    static func encode(contacts: [CNContact]) -> String? {
        let records: [GuestRecord] = contacts.map { contact in
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.givenName
            let email = contact.emailAddresses.first.map { $0.value as String }
            return GuestRecord(name: name, email: email)
        }
        guard !records.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(records) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> [GuestRecord] {
        guard let json,
              let data = json.data(using: .utf8),
              let records = try? JSONDecoder().decode([GuestRecord].self, from: data)
        else { return [] }
        return records
    }
}
