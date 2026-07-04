// ICSFeedFetcher.swift
// Feature: Calendar
// Purpose: Network fetch + parse for ICS/RSS subscription feeds off the main actor.

import Foundation
import CollegeCalendar

actor ICSFeedFetcher {
    static let shared = ICSFeedFetcher()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 30
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }

    func fetchEvents(
        urlString: String,
        feedKind: CalendarFeedKind
    ) async throws -> [ICSCalendarParser.ParsedEvent] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        return try CalendarFeedParser.parse(
            data: data,
            urlString: urlString,
            kind: feedKind
        )
    }
}
