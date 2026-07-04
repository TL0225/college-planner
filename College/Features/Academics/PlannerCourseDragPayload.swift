// PlannerCourseDragPayload.swift
// Feature: Academics
// Purpose: Lightweight drag payload for moving a course from the Requirements
//          Breakdown onto a semester block (and onto requirement buckets).
//
// Encoded as a JSON string so it rides the existing String-based drag/drop plumbing
// (`.draggable(String)` / `.dropDestination(for: String.self)` / `NSItemProvider` text)
// without needing a registered UTType. Decoding tolerates a bare course code so older
// drop targets that only expect a code keep working.

import Foundation

struct PlannerCourseDragPayload: Codable, Equatable, Sendable {
    let code: String
    let title: String
    let credits: String

    init(code: String, title: String = "", credits: String = "") {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.credits = credits.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON string used as the drag item. Falls back to the bare code if encoding fails.
    var encoded: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return code
        }
        return json
    }

    /// Parses a dragged string back into a payload. Accepts either the JSON form or a
    /// plain course code (legacy / external drags).
    static func decode(_ raw: String) -> PlannerCourseDragPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return PlannerCourseDragPayload(code: "") }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PlannerCourseDragPayload.self, from: data) {
            return decoded
        }
        return PlannerCourseDragPayload(code: trimmed)
    }

    /// Integer credit value parsed from the credits string ("3", "3 cr", "3-4" → 3).
    var creditValue: Int {
        RequirementBreakdownCredits.creditValue(from: credits)
    }
}
