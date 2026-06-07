// CourseLeafSitemapCache.swift
// Feature: Catalog
// Purpose: Deduplicate CourseLeaf sitemap.xml fetches within a single ingest run.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// In-memory sitemap page URL cache keyed by normalized catalog base URL (host + path).
enum CourseLeafSitemapCache {
    private actor Storage {
        private var entries: [String: [URL]] = [:]
        private var fetchXML: @Sendable (URL) async throws -> String = defaultFetchXML

        func clear() {
            entries.removeAll()
        }

        func setFetchXMLForTesting(_ fetch: @escaping @Sendable (URL) async throws -> String) {
            fetchXML = fetch
            entries.removeAll()
        }

        func resetFetchXMLForTesting() {
            fetchXML = defaultFetchXML
            entries.removeAll()
        }

        func pageURLs(baseURL: URL) async throws -> [URL] {
            let key = cacheKey(for: baseURL)
            if let cached = entries[key] {
                return cached
            }
            let urls = try await loadPageURLs(baseURL: baseURL)
            entries[key] = urls
            return urls
        }

        private func loadPageURLs(baseURL: URL) async throws -> [URL] {
            let sitemapURL = baseURL.appendingPathComponent("sitemap.xml")
            return try await discoverPageURLs(
                from: sitemapURL,
                fallbackBaseURL: baseURL,
                fetchXML: fetchXML
            )
        }
    }

    private static let storage = Storage()

    private static func defaultFetchXML(from url: URL) async throws -> String {
        try await CourseLeafXMLClient.fetchXML(from: url)
    }

    /// Clears cached sitemap page lists (call at the start of a CourseLeaf sync).
    static func clear() async {
        await storage.clear()
    }

    static func pageURLs(baseURL: URL) async throws -> [URL] {
        try await storage.pageURLs(baseURL: baseURL)
    }

    /// Replaces the XML fetch used for sitemap discovery (tests only).
    static func setFetchXMLForTesting(_ fetch: @escaping @Sendable (URL) async throws -> String) async {
        await storage.setFetchXMLForTesting(fetch)
    }

    static func resetFetchXMLForTesting() async {
        await storage.resetFetchXMLForTesting()
    }

    static func cacheKey(for baseURL: URL) -> String {
        let host = (baseURL.host ?? "").lowercased()
        var path = baseURL.path
        if path.isEmpty {
            path = "/"
        } else if !path.hasSuffix("/") {
            path += "/"
        }
        return "\(host)\(path)"
    }

    private static func discoverPageURLs(
        from sitemapURL: URL,
        fallbackBaseURL: URL,
        fetchXML: @Sendable (URL) async throws -> String
    ) async throws -> [URL] {
        let xml = try await fetchXML(sitemapURL)
        let locPattern = try NSRegularExpression(
            pattern: "<loc>(.*?)</loc>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = locPattern.matches(in: xml, options: [], range: nsRange)

        var urls: [URL] = []
        urls.reserveCapacity(matches.count)
        for match in matches {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            let raw = xml[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), let host = url.host, host == fallbackBaseURL.host else { continue }
            urls.append(url)
        }

        if urls.isEmpty {
            return [fallbackBaseURL]
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }
}
