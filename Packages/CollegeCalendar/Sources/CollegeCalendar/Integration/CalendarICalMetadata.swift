// CalendarICalMetadata.swift
// Feature: Calendar
// Purpose: Parse College-specific metadata embedded in iCalendar payloads.

import Foundation

public enum CalendarICalMetadata {
    /// Reads `X-COLLEGE-LOCAL-ID` from a VEVENT block.
    public static func localEventUUID(fromICal ical: String) -> UUID? {
        let lines =
            ical
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: .newlines)

        var inEvent = false
        for line in lines {
            if line.uppercased() == "BEGIN:VEVENT" {
                inEvent = true
                continue
            }
            if line.uppercased() == "END:VEVENT" { break }
            guard inEvent else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).components(separatedBy: ";").first ?? ""
            if key.uppercased() == "X-COLLEGE-LOCAL-ID" {
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return UUID(uuidString: value)
            }
        }
        return nil
    }
}
