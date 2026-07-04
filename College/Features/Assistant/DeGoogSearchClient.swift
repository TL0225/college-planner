// DeGoogSearchClient.swift
// Feature: Assistant
// Purpose: JSON client for the local or custom DeGoog `/api/search` endpoint.

import Foundation

enum DeGoogSearchClientError: LocalizedError, Equatable {
  case disabled
  case sidecarUnavailable
  case invalidURL
  case badStatus(Int)
  case emptyBody
  case decodeFailed

  var errorDescription: String? {
    switch self {
    case .disabled:
      return "Web search is turned off in Settings."
    case .sidecarUnavailable:
      return "Built-in web search is unavailable in this environment."
    case .invalidURL:
      return "Could not build a valid web search URL."
    case .badStatus(let code):
      return "Web search returned HTTP \(code)."
    case .emptyBody:
      return "Web search returned an empty response."
    case .decodeFailed:
      return "Could not parse web search JSON."
    }
  }
}

/// DeGoog JSON client (`GET /api/search?q=…`).
struct DeGoogSearchClient: Sendable {
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
    guard AssistantWebSearchSettings.isWebSearchEnabled else {
      throw DeGoogSearchClientError.disabled
    }

    let base = try await DeGoogSidecarManager.shared.resolvedBaseURL()
    let capped = max(1, min(maxResults, 12))
    let data = try await requestSearchData(base: base, query: query)
    return try Self.parseResults(data: data, maxResults: capped)
  }

  private func requestSearchData(base: URL, query: String) async throws -> Data {
    var components = URLComponents(url: base.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "type", value: "web"),
      URLQueryItem(name: "lang", value: Locale.current.language.languageCode?.identifier ?? "en"),
    ]
    guard let url = components?.url else {
      throw DeGoogSearchClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 25
    request.setValue("College/1.0 (DeGoog client)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DeGoogSearchClientError.badStatus(-1)
    }
    guard (200...299).contains(http.statusCode) else {
      throw DeGoogSearchClientError.badStatus(http.statusCode)
    }
    guard !data.isEmpty else { throw DeGoogSearchClientError.emptyBody }
    return data
  }

  static func parseResults(data: Data, maxResults: Int) throws -> [Hit] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = root["results"] as? [[String: Any]]
    else {
      throw DeGoogSearchClientError.decodeFailed
    }

    var hits: [Hit] = []
    hits.reserveCapacity(min(maxResults, results.count))
    for row in results.prefix(maxResults) {
      let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let urlStr = (row["url"] as? String) ?? ""
      let content = (row["content"] as? String)
        ?? (row["snippet"] as? String)
        ?? ""
      let engine = (row["source"] as? String)
        ?? (row["sources"] as? [String])?.first
      guard !title.isEmpty || !urlStr.isEmpty else { continue }
      let clipped = String(content.prefix(900))
      hits.append(Hit(title: title.isEmpty ? urlStr : title, url: urlStr, content: clipped, engine: engine))
    }
    if hits.isEmpty { throw DeGoogSearchClientError.decodeFailed }
    return hits
  }
}
