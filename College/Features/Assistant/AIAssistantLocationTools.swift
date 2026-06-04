// AIAssistantLocationTools.swift
// Feature: Assistant
// Purpose: Assistant module — ResolvedEventLocationPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ResolvedEventLocationPayload: Codable {
    let title: String
    let startISO8601: String
    let endISO8601: String?
    let location: String
    let notes: String?
    let disambiguationCount: Int
}

@MainActor
struct ResolveEventLocationTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let eventTitleQuery: String
        let nearDateISO8601: String?
        let preferUpcoming: Bool?
    }

    let descriptor = AssistantToolDescriptor(
        name: "resolveEventLocation",
        description: "Find where a calendar event takes place (room/building string, not a map).",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"eventTitleQuery\":\"CSC 316\",\"nearDateISO8601?\":\"2026-05-20\",\"preferUpcoming?\":true}",
        outputSchemaDescription: "title, startISO8601, location, notes",
        sourceLabel: "CalendarEventEntity"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let query = decoded.eventTitleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("eventTitleQuery required")
        }
        var matches = CalendarEventSearchBridge.search(
            query: query,
            semester: nil,
            limit: 50,
            collegePersistence: context.collegePersistence
        )
        if let nearRaw = decoded.nearDateISO8601, let near = ISO8601DateFormatter().date(from: nearRaw) {
            matches = matches.filter {
                abs($0.startDate.timeIntervalSince(near)) < 86_400 * 3
            }
        }
        if decoded.preferUpcoming ?? true {
            let now = context.currentDate
            matches.sort { $0.startDate < $1.startDate }
            if let upcoming = matches.first(where: { $0.startDate >= now }) {
                matches = [upcoming] + matches.filter { $0.id != upcoming.id }
            }
        }
        guard let event = matches.first else {
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: ["matches": .number(0)],
                source: descriptor.sourceLabel,
                summary: "No event matched \"\(query)\".",
                errorMessage: nil
            )
        }
        let formatter = ISO8601DateFormatter()
        let location = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ResolvedEventLocationPayload(
            title: event.title,
            startISO8601: formatter.string(from: event.startDate),
            endISO8601: event.endDate.map { formatter.string(from: $0) },
            location: location,
            notes: event.notes,
            disambiguationCount: matches.count
        )
        let summary: String
        if location.isEmpty {
            summary = "Found \"\(payload.title)\" but no location is saved yet. Offer updateCalendarEvent to add one."
        } else {
            summary = "\"\(payload.title)\" is at \(location)."
        }
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: summary,
            errorMessage: nil
        )
    }
}
