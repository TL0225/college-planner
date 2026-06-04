// CourseLeafXMLClient.swift
// Feature: Catalog
// Purpose: Catalog module — CourseLeafXMLClient.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Shared HTTP + URL helpers for CourseLeaf `index.xml` and `sitemap.xml` fetches.
enum CourseLeafXMLClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }()

    static func normalizedIndexURL(from pageURL: URL) -> URL {
        let lowerPath = pageURL.path.lowercased()
        if lowerPath.hasSuffix("/index.xml") || lowerPath.hasSuffix(".xml") {
            return pageURL
        }
        if pageURL.hasDirectoryPath {
            return pageURL.appendingPathComponent("index.xml")
        }
        return pageURL.appendingPathComponent("index.xml")
    }

    static func fetchXML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/xml,text/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ScraperError.invalidResponse
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("xml") else {
            throw ScraperError.invalidResponse
        }
        guard let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else {
            throw ScraperError.parsingFailed
        }
        return decoded
    }

    static func fetchIndexXML(forProgramURL programURLString: String) async throws -> String {
        let trimmed = programURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: trimmed) else { throw ScraperError.invalidURL }
        return try await fetchXML(from: normalizedIndexURL(from: pageURL))
    }
}
