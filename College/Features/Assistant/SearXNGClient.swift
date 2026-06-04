// SearXNGClient.swift
// Feature: Assistant
// Purpose: Assistant module — SearXNGClient.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum SearXNGClientError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case badStatus(Int)
    case emptyBody
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SearXNG is not configured. Add your instance URL in Settings > Privacy & Security > AI & Storage."
        case .invalidURL:
            return "Could not build a valid SearXNG search URL."
        case .badStatus(let code):
            return "SearXNG returned HTTP \(code)."
        case .emptyBody:
            return "SearXNG returned an empty response."
        case .decodeFailed:
            return "Could not parse SearXNG JSON."
        }
    }
}

/// Minimal SearXNG JSON client (`/search?format=json`).
struct SearXNGClient: Sendable {

    struct Hit: Sendable, Encodable {
        let title: String
        let url: String
        let content: String
        let engine: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validateConfiguration() async throws {
        _ = try await search(query: "college", maxResults: 1)
    }

    func search(query: String, maxResults: Int = 8) async throws -> [Hit] {
        guard let base = AssistantWebSearchSettings.normalizedSearxBaseURL(AssistantWebSearchSettings.searxBaseURL) else {
            throw SearXNGClientError.notConfigured
        }

        let capped = max(1, min(maxResults, 12))

        do {
            let data = try await requestSearchData(base: base, query: query, includeStartpageEngine: true)
            return try Self.parseResults(data: data, maxResults: capped)
        } catch let err as SearXNGClientError {
            // Some public SearXNG instances intermittently reject engine-constrained queries.
            // Retry once with default instance engines so users still get web results.
            if case .badStatus(503) = err {
                let data = try await requestSearchData(base: base, query: query, includeStartpageEngine: false)
                return try Self.parseResults(data: data, maxResults: capped)
            }
            throw err
        }
    }

    private func requestSearchData(base: URL, query: String, includeStartpageEngine: Bool) async throws -> Data {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "safesearch", value: "1")
        ]
        if includeStartpageEngine {
            queryItems.append(URLQueryItem(name: "engines", value: "startpage"))
        }

        var components = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SearXNGClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("College/1.0 (SearXNG client)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SearXNGClientError.badStatus(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SearXNGClientError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw SearXNGClientError.emptyBody }
        return data
    }

    private static func parseResults(data: Data, maxResults: Int) throws -> [Hit] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else {
            throw SearXNGClientError.decodeFailed
        }

        var hits: [Hit] = []
        hits.reserveCapacity(min(maxResults, results.count))
        for row in results.prefix(maxResults) {
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let urlStr = (row["url"] as? String) ?? ""
            let content = (row["content"] as? String) ?? (row["snippet"] as? String) ?? ""
            let engine = row["engine"] as? String
            guard !title.isEmpty || !urlStr.isEmpty else { continue }
            let clipped = String(content.prefix(900))
            hits.append(Hit(title: title.isEmpty ? urlStr : title, url: urlStr, content: clipped, engine: engine))
        }
        if hits.isEmpty { throw SearXNGClientError.decodeFailed }
        return hits
    }
}
