// ModernCampusPolicyIngestion.swift
// Feature: Catalog
// Purpose: Catalog module — PolicyChunkRow.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation
import SwiftSoup

/// Bounded Modern Campus **academic policy** ingestion: sidebar / index `navoid` discovery, keyword scoring,
/// and `h2`/`h3`-bounded text chunks for RAG (not monolithic `content.php` blobs).
enum ModernCampusPolicyIngestion {
    struct PolicyChunkRow: Sendable, Equatable {
        let catoid: String
        let sourceURL: String
        let navTitle: String
        let sectionHeading: String?
        let bodyText: String
        let catalogScope: String
        let contentHash: String
    }

    private static let policyKeywords: [(String, Int)] = [
        ("academic regulation", 40),
        ("academic policy", 38),
        ("grading policy", 36),
        ("grading", 18),
        ("academic standing", 28),
        ("academic integrity", 26),
        ("honor code", 22),
        ("repeat", 20),
        ("withdrawal", 18),
        ("transfer credit", 32),
        ("transfer", 14),
        ("general education", 24),
        ("gen ed", 20),
        ("catalog rights", 16),
        ("tuition", 8),
        ("admission", 6),
    ]

    /// Discovers up to `maxNavLinks` scored `navoid` targets from the catalog index for a `catoid`.
    static func discoverPolicyNavCandidates(baseURL: String, catoid: String, maxNavLinks: Int) async throws -> [(title: String, url: String, score: Int)] {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let indexURL = URL(string: trimmedBase)?.appendingPathComponent("index.php") else { return [] }
        var components = URLComponents(url: indexURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "catoid" }
        items.append(URLQueryItem(name: "catoid", value: catoid))
        components?.queryItems = items
        guard let urlString = components?.string else { return [] }

        let html = try await ModernCampusEngine.fetchHTMLPublic(urlString)
        let doc = try SwiftSoup.parse(html, urlString)
        let body = doc.body() ?? doc
        let links = try body.select("a[href*=navoid=]")

        var scored: [(title: String, url: String, score: Int)] = []
        scored.reserveCapacity(32)

        for a in links.array() {
            let href = (try? a.attr("abs:href")) ?? ""
            guard href.contains("navoid=") else { continue }
            let forced = forceCatoid(href, catalogID: catoid)
            guard let u = URL(string: forced), u.scheme?.hasPrefix("http") == true else { continue }
            let title = ((try? a.text()) ?? "").normalizedCatalogText()
            guard !title.isEmpty else { continue }
            let score = navPolicyScore(linkText: title)
            guard score > 0 else { continue }
            if scored.contains(where: { $0.url == forced }) { continue }
            scored.append((title: title, url: forced, score: score))
        }

        scored.sort { $0.score > $1.score }
        if scored.count > maxNavLinks {
            scored = Array(scored.prefix(maxNavLinks))
        }
        return scored
    }

    /// Fetches scored nav pages, splits main content on `h2`/`h3`, caps section size, and attaches `CatalogPolicyScope`.
    static func fetchPolicyChunks(
        baseURL: String,
        catalogTitle: String,
        catoid: String,
        maxNavFetches: Int = 8
    ) async throws -> [PolicyChunkRow] {
        let label = ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: catalogTitle, catoid: catoid)
        let nav = try await discoverPolicyNavCandidates(baseURL: baseURL, catoid: catoid, maxNavLinks: max(1, maxNavFetches * 2))
        let top = Array(nav.prefix(maxNavFetches))

        var rows: [PolicyChunkRow] = []
        for item in top {
            await Task.yield()
            let scope = CatalogPolicyScopeClassifier.scope(catalogTypeLabel: label, navLinkText: item.title).rawValue
            let html = try await ModernCampusEngine.fetchHTMLPublic(item.url)
            let sections = try chunkSections(html: html, baseURL: item.url, navTitle: item.title)
            for sec in sections {
                let hash = sha256Hex("\(item.url)|\(sec.heading)|\(sec.text)")
                rows.append(
                    PolicyChunkRow(
                        catoid: catoid,
                        sourceURL: item.url,
                        navTitle: item.title,
                        sectionHeading: sec.heading,
                        bodyText: sec.text,
                        catalogScope: scope,
                        contentHash: hash
                    )
                )
            }
        }
        return rows
    }

    // MARK: - Internals

    private struct Section: Sendable {
        let heading: String
        let text: String
    }

    private static func navPolicyScore(linkText: String) -> Int {
        let t = linkText.lowercased()
        var s = 0
        for (needle, weight) in policyKeywords where t.contains(needle) {
            s += weight
        }
        return s
    }

    private static func chunkSections(html: String, baseURL: String, navTitle: String) throws -> [Section] {
        let doc = try SwiftSoup.parse(html, baseURL)
        let root =
            (try? doc.select("td.block_content").first())
            ?? (try? doc.select("#acalog-content").first())
            ?? (try? doc.select("div.acalog-content").first())
            ?? doc.body()
            ?? doc

        var sections: [Section] = []
        var currentHeading = navTitle
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n").normalizedCatalogText()
            buffer.removeAll(keepingCapacity: true)
            guard joined.count > 40 else { return }
            for piece in splitOversizedSection(text: joined, maxWords: 420) {
                sections.append(Section(heading: currentHeading, text: piece))
            }
        }

        func walk(_ element: Element) throws {
            let tag = element.tagName().lowercased()
            if tag == "h2" || tag == "h3" {
                flush()
                currentHeading = ((try? element.text()) ?? "").normalizedCatalogText()
                if currentHeading.isEmpty { currentHeading = navTitle }
                return
            }
            if tag == "script" || tag == "style" || tag == "noscript" { return }

            if tag == "p" || tag == "li" {
                let line = ((try? element.text()) ?? "").normalizedCatalogText()
                if !line.isEmpty { buffer.append(line) }
                return
            }

            for child in element.children() {
                try walk(child)
            }
        }

        try walk(root)
        flush()

        if sections.isEmpty {
            var second: [Section] = []
            let headings = try root.select("h2, h3")
            for h in headings.array() {
                let headingText = ((try? h.text()) ?? "").normalizedCatalogText()
                let tail = try collectHeadingSiblingTail(from: h)
                guard tail.count > 40 else { continue }
                for piece in splitOversizedSection(text: tail, maxWords: 420) {
                    second.append(Section(heading: headingText.isEmpty ? navTitle : headingText, text: piece))
                }
            }
            if !second.isEmpty {
                sections = second
                DebugLogger.shared.log(
                    "ModernCampusPolicyIngestion: used h2/h3 sibling-tail chunking (DOM walk produced no sections)",
                    category: .system,
                    level: .info
                )
            }
        }

        if sections.isEmpty {
            let fallback = ((try? root.text()) ?? "").normalizedCatalogText()
            if fallback.count > 80 {
                DebugLogger.shared.log(
                    "ModernCampusPolicyIngestion: whole-page text fallback after empty structured sections",
                    category: .system,
                    level: .info
                )
                for piece in splitOversizedSection(text: fallback, maxWords: 420) {
                    sections.append(Section(heading: navTitle, text: piece))
                }
            }
        }

        return sections
    }

    /// Collects paragraph/list/div text following a heading until the next `h2`/`h3` sibling.
    private static func collectHeadingSiblingTail(from heading: Element) throws -> String {
        var parts: [String] = []
        var el = try heading.nextElementSibling()
        while let node = el {
            let tag = node.tagName().lowercased()
            if tag == "h2" || tag == "h3" { break }
            if tag == "p" || tag == "li" {
                let line = ((try? node.text()) ?? "").normalizedCatalogText()
                if !line.isEmpty { parts.append(line) }
            } else if tag == "div" || tag == "section" || tag == "article" {
                let innerPs = try node.select("p, li")
                if innerPs.array().isEmpty {
                    let block = ((try? node.text()) ?? "").normalizedCatalogText()
                    if !block.isEmpty { parts.append(block) }
                } else {
                    for p in innerPs.array() {
                        let line = ((try? p.text()) ?? "").normalizedCatalogText()
                        if !line.isEmpty { parts.append(line) }
                    }
                }
            }
            el = try node.nextElementSibling()
        }
        return parts.joined(separator: "\n").normalizedCatalogText()
    }

    private static func splitOversizedSection(text: String, maxWords: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > maxWords else { return [text] }
        var out: [String] = []
        var i = 0
        while i < words.count {
            let end = min(i + maxWords, words.count)
            out.append(words[i..<end].joined(separator: " "))
            i = end
        }
        return out
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func forceCatoid(_ href: String, catalogID: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return href }
        var items = components.queryItems ?? []
        if let idx = items.firstIndex(where: { $0.name.lowercased() == "catoid" }) {
            items[idx] = URLQueryItem(name: "catoid", value: catalogID)
        } else {
            items.append(URLQueryItem(name: "catoid", value: catalogID))
        }
        components.queryItems = items
        return components.string ?? trimmed
    }
}

extension ModernCampusPolicyIngestion {
    /// HTML fixture helper for `CollegeTests` (same file as private `chunkSections`).
    static func test_policySections(html: String, baseURL: String, navTitle: String) throws -> [(heading: String, text: String)] {
        try chunkSections(html: html, baseURL: baseURL, navTitle: navTitle).map { (heading: $0.heading, text: $0.text) }
    }
}
