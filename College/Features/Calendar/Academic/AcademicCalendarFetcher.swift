// AcademicCalendarFetcher.swift
// Feature: Calendar
// Purpose: Fetch academic calendar pages (static HTML + rendered fallback).

import Foundation

struct AcademicCalendarFetchResult: Sendable {
    var content: String
    var isHTML: Bool
    var etag: String?
    var lastModified: String?
    var statusCode: Int
}

enum AcademicCalendarFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    static func headValidate(urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    static func fetch(
        urlString: String,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> AcademicCalendarFetchResult {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified, !lastModified.isEmpty { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 304 {
            return AcademicCalendarFetchResult(content: "", isHTML: true, etag: etag, lastModified: lastModified, statusCode: 304)
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.init(rawValue: http.statusCode))
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let reduced = reduceHTMLToText(html)
        let reducedDateDensity = estimateDateDensity(reduced)
        let preClassification = AcademicCalendarPageClassifier.classify(
            content: html,
            baseURL: url,
            forcedMode: nil
        )
        let preserveRawHTML = preClassification.kind == .hasICSFeed || preClassification.kind == .indexHub
        let shouldRender = !preserveRawHTML && (
            html.count < 400
            || looksJSHeavy(html)
            || (reducedDateDensity < 5 && html.count > 400)
        )

        if shouldRender {
            if let host = url.host?.lowercased() {
                AssistantWebFetchPolicy.registerPolicyHosts([host])
            }
            if let rendered = try? await AssistantWebPageExtractor.shared.fetchReadableText(from: url, maxCharacters: 120_000) {
                let text = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, estimateDateDensity(text) >= reducedDateDensity {
                    return AcademicCalendarFetchResult(
                        content: text,
                        isHTML: false,
                        etag: http.value(forHTTPHeaderField: "ETag"),
                        lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                        statusCode: http.statusCode
                    )
                }
            }
        }

        return AcademicCalendarFetchResult(
            content: html,
            isHTML: true,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            statusCode: http.statusCode
        )
    }

    static func fetchHTMLRaw(urlString: String) async throws -> String {
        try await ModernCampusEngine.fetchHTMLPublic(urlString)
    }

    private static func looksJSHeavy(_ html: String) -> Bool {
        let lower = html.lowercased()
        let hasFilter = lower.contains("filter options") || lower.contains("add to my calendar")
        let fewDates = estimateDateDensity(lower) < 3
        return hasFilter && fewDates
    }

    private static func estimateDateDensity(_ content: String) -> Int {
        let pattern = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
    }

    static func reduceHTMLToText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "\\s+\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentHash(_ content: String) -> String {
        AcademicCalendarIdentityResolver.stableHash(content)
    }
}
