// CalendarGuestInviteExporter.swift
// Feature: Calendar
// Purpose: Guest roster export helpers for connected calendar providers.

import Foundation

public enum CalendarGuestInviteExporter {
    public static func hasInviteRecipients(in attendeesJSON: String?) -> Bool {
        !CalendarEventGuestsCodec.decode(attendeesJSON).filter { guest in
            let email = guest.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !email.isEmpty
        }.isEmpty
    }

    public static func outlookAttendees(from attendeesJSON: String?) -> [OutlookAttendeeUpload] {
        CalendarEventGuestsCodec.decode(attendeesJSON).compactMap { guest in
            let email = guest.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !email.isEmpty else { return nil }
            let name = guest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return OutlookAttendeeUpload(
                emailAddress: OutlookEmailAddress(
                    address: email,
                    name: name.isEmpty ? nil : name
                ),
                type: "required"
            )
        }
    }

    public static func icalAttendeeLines(from attendeesJSON: String?) -> [String] {
        CalendarEventGuestsCodec.decode(attendeesJSON).compactMap { guest in
            let email = guest.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !email.isEmpty else { return nil }
            let name = guest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cn = name.isEmpty ? email : name
            return "ATTENDEE;CN=\(icalEscape(cn));ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:\(email)"
        }
    }

    /// Apple EventKit cannot attach invitees programmatically; mirror guest roster in notes.
    public static func appleNotesWithGuestRoster(notes: String?, attendeesJSON: String?) -> String? {
        let guests = CalendarEventGuestsCodec.decode(attendeesJSON)
            .compactMap { guest -> String? in
                let email = guest.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !email.isEmpty else { return nil }
                let name = guest.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? email : "\(name) <\(email)>"
            }
        guard !guests.isEmpty else {
            return notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? notes : nil
        }

        let rosterHeader = "[guests]"
        let rosterBody = guests.joined(separator: "\n")
        let existing = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.contains(rosterHeader) {
            return existing.isEmpty ? nil : existing
        }
        if existing.isEmpty {
            return "\(rosterHeader)\n\(rosterBody)"
        }
        return existing + "\n\n" + rosterHeader + "\n" + rosterBody
    }

    private static func icalEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }
}

public struct OutlookAttendeeUpload: Encodable, Sendable {
    public let emailAddress: OutlookEmailAddress
    public let type: String
}

public struct OutlookEmailAddress: Encodable, Sendable {
    public let address: String
    public let name: String?

    public init(address: String, name: String?) {
        self.address = address
        self.name = name
    }
}
