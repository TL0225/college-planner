// CalendarSyncNotesMetadata.swift
// Feature: Calendar
// Purpose: Parse course UUID tags and related metadata embedded in event notes.

import Foundation

public enum CalendarSyncNotesMetadata {
    private static let courseTagPattern = #"\[course_uuid\]=([0-9A-Fa-f-]{36})"#

    /// Extracts a planner course UUID from notes like `[course_uuid]=…`.
    public static func courseUUID(from notes: String?) -> UUID? {
        guard let notes,
              let regex = try? NSRegularExpression(pattern: courseTagPattern)
        else { return nil }
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        guard let match = regex.firstMatch(in: notes, range: range),
              match.numberOfRanges > 1,
              let uuidRange = Range(match.range(at: 1), in: notes)
        else { return nil }
        return UUID(uuidString: String(notes[uuidRange]))
    }
}
