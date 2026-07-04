// ModernCampusCatalogDiscoverer.swift
// Feature: Catalog
// Purpose: Discovery-only CatalogGraph builder for Modern Campus / Acalog hosts.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation
import SwiftSoup

/// Discovery-only Modern Campus graph builder (no program page scraping).
enum ModernCampusCatalogDiscoverer {
    private static let engineID = "moderncampus"

    struct SidebarEntry: Sendable, Equatable {
        let label: String
        let url: String
        let navoid: String?
    }

    static func buildGraph(
        manifest: SchoolManifest,
        baseURL: URL,
        discoveredAt: Date = Date()
    ) async throws -> CatalogGraph {
        let normalized = baseURL.absoluteString
        let (_, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(normalized)
        let catalogsToUse = await ModernCampusCatalogDiscovery.resolveCatalogsForIngestLenient(
            normalizedBaseURL: normalized,
            catoidHint: catoidHint
        )
        guard !catalogsToUse.isEmpty else {
            throw ScraperError.invalidURL
        }
        return try await buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            catalogs: catalogsToUse,
            discoveredAt: discoveredAt
        )
    }

    static func buildGraph(
        manifest: SchoolManifest,
        baseURL: URL,
        catalogs: [ModernCampusCatalogDescriptor],
        discoveredAt: Date = Date()
    ) async throws -> CatalogGraph {
        var sidebarByCatoid: [String: [SidebarEntry]] = [:]
        for catalog in catalogs {
            let catoid = catalog.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !catoid.isEmpty else { continue }
            let indexURL = indexURL(baseURL: baseURL, catoid: catoid)
            let html = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
            sidebarByCatoid[catoid] = parseSidebarLinks(html: html, baseURL: baseURL, catoid: catoid)
        }

        var extraPageURLs: [String] = []
        if ModernCampusHostProfiles.resolve(host: baseURL.host)?.prefersEntityPageProgramDiscovery == true {
            extraPageURLs = try await discoverEntityLinkedProgramURLs(
                baseURL: baseURL,
                catalogs: catalogs,
                sidebarByCatoid: sidebarByCatoid
            )
        }

        return buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            catalogs: catalogs,
            sidebarByCatoid: sidebarByCatoid,
            extraPageURLs: extraPageURLs,
            discoveredAt: discoveredAt
        )
    }

    /// Offline graph build from explicit URLs (unit tests; no network).
    static func buildGraph(
        manifest: SchoolManifest,
        baseURL: URL,
        catalogs: [ModernCampusCatalogDescriptor],
        pageURLs: [String],
        sidebarByCatoid: [String: [SidebarEntry]] = [:],
        discoveredAt: Date = Date()
    ) -> CatalogGraph {
        buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            catalogs: catalogs,
            sidebarByCatoid: sidebarByCatoid,
            extraPageURLs: pageURLs,
            discoveredAt: discoveredAt
        )
    }

    private static func buildGraph(
        manifest: SchoolManifest,
        baseURL: URL,
        catalogs: [ModernCampusCatalogDescriptor],
        sidebarByCatoid: [String: [SidebarEntry]],
        extraPageURLs: [String],
        discoveredAt: Date
    ) -> CatalogGraph {
        let schoolID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifestVersion = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)

        var nodes: [CatalogPageNode] = []
        var urlSet = Set<String>()
        var signatureURLs: [String] = []

        func appendNode(_ node: CatalogPageNode) {
            guard urlSet.insert(node.url).inserted else { return }
            nodes.append(node)
            signatureURLs.append(node.url)
        }

        for catalog in catalogs {
            let catoid = catalog.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !catoid.isEmpty else { continue }
            let version = CatalogVersion.resolve(school: manifest, segment: .modernCampus(catalog))
            let indexURLString = indexURL(baseURL: baseURL, catoid: catoid).absoluteString

            let indexNode = CatalogPageNode(
                url: indexURLString,
                kind: .index,
                parentNodeID: nil,
                depth: 0,
                catalogVersionID: version.id,
                discoveryConfidence: 1.0
            )
            appendNode(indexNode)

            let sidebar = sidebarByCatoid[catoid] ?? []
            for entry in sidebar {
                var kind = classifyPageKind(url: entry.url, linkLabel: entry.label)
                if kind == .unknown {
                    kind = reclassifyUnknownPageKind(
                        url: entry.url,
                        linkLabel: entry.label,
                        host: baseURL.host
                    )
                }
                appendNode(
                    CatalogPageNode(
                        url: entry.url,
                        kind: kind,
                        parentNodeID: indexNode.id,
                        depth: 1,
                        catalogVersionID: version.id,
                        discoveryConfidence: kind == .unknown ? 0.6 : 0.95
                    )
                )
            }
        }

        for raw in extraPageURLs {
            let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            let matchingCatalog = catalogs.first { descriptor in
                let catoid = descriptor.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
                return !catoid.isEmpty && url.contains("catoid=\(catoid)")
            }
            let versionID: String
            if let matchingCatalog {
                versionID = CatalogVersion.resolve(school: manifest, segment: .modernCampus(matchingCatalog)).id
            } else {
                versionID = manifestVersion.id
            }
            appendNode(
                CatalogPageNode(
                    url: url,
                    kind: classifyPageKind(url: url),
                    parentNodeID: nil,
                    depth: pathDepth(url),
                    catalogVersionID: versionID,
                    discoveryConfidence: 1.0
                )
            )
        }

        let sourceSignature = computeSignature(from: signatureURLs, schoolID: schoolID)
        return CatalogGraph(
            schoolID: schoolID,
            catalogVersionID: manifestVersion.id,
            engine: engineID,
            nodes: nodes,
            discoveredAt: discoveredAt,
            sourceSignature: sourceSignature
        )
    }

    static func classifyPageKind(url: String, linkLabel: String? = nil) -> CatalogPageKind {
        let lower = url.lowercased()
        let labelLower = (linkLabel ?? "").lowercased()

        if lower.contains("preview_program") {
            return .programDetail
        }
        if lower.contains("preview_entity") {
            return .programListing
        }
        if lower.contains("preview_course_nopop") || lower.contains("preview_course.php") || lower.contains("preview_course") {
            return .courseDetail
        }
        if isPolicyURL(lower) || isPolicyLabel(labelLower) {
            return .policy
        }
        if lower.contains("index.php"), !lower.contains("preview_"), !lower.contains("content.php") {
            return .index
        }
        if isCourseListingURL(lower) || isCourseListingLabel(labelLower) {
            return isCourseDetailURL(lower) ? .courseDetail : .courseListing
        }
        if isProgramListingURL(lower, labelLower: labelLower) {
            return .programListing
        }
        if lower.contains("content.php"), lower.contains("navoid=") {
            return .unknown
        }
        return .unknown
    }

    static func parseSidebarLinks(html: String, baseURL: URL, catoid: String) -> [SidebarEntry] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return [] }
        let anchors = ModernCampusSidebarParsing.anchors(in: doc)
        if anchors.isEmpty { return [] }

        var out: [SidebarEntry] = []
        var seen = Set<String>()
        for anchor in anchors {
            let hrefRaw = ((try? anchor.attr("abs:href")) ?? (try? anchor.attr("href")) ?? "")
                .replacingOccurrences(of: "&amp;", with: "&")
            let label = ((try? anchor.text()) ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !hrefRaw.isEmpty else { continue }

            if let hrefCatoid = extractQueryParameter("catoid", from: hrefRaw), hrefCatoid != catoid {
                continue
            }
            let resolved = ModernCampusEngine.acalogURLForcingCatoid(hrefRaw, catoid: catoid)
            guard seen.insert(resolved).inserted else { continue }
            let navoid = extractQueryParameter("navoid", from: resolved)
            guard resolved.contains("navoid=") else { continue }
            out.append(SidebarEntry(label: label, url: resolved, navoid: navoid))
        }
        return out
    }

    static func indexURL(baseURL: URL, catoid: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("index.php"), resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "catoid" }
        items.append(URLQueryItem(name: "catoid", value: catoid))
        components?.queryItems = items
        return components?.url ?? baseURL
    }

    private static func extractQueryParameter(_ param: String, from urlString: String) -> String? {
        guard let url = URLComponents(string: urlString) else { return nil }
        return url.queryItems?.first(where: { $0.name.lowercased() == param.lowercased() })?.value
    }

    private static func pathDepth(_ urlString: String) -> Int {
        guard let path = URL(string: urlString)?.path else { return 0 }
        return path.split(separator: "/").filter { !$0.isEmpty }.count
    }

    private static func isPolicyURL(_ lower: String) -> Bool {
        let hints = [
            "academic-regulation", "academic-regulations", "academic-policy", "academic-policies",
            "grading-policy", "honor-code", "academic-integrity", "general-education"
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func isPolicyLabel(_ lower: String) -> Bool {
        let hints = [
            "academic regulation", "academic policy", "grading policy", "academic integrity",
            "honor code", "general education", "catalog rights"
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func isCourseListingURL(_ lower: String) -> Bool {
        lower.contains("preview_course") == false
            && (lower.contains("course-descriptions")
                || lower.contains("coursedescriptions")
                || (lower.contains("content.php") && lower.contains("navoid=") && lower.contains("course")))
    }

    private static func isCourseListingLabel(_ lower: String) -> Bool {
        lower == "courses"
            || lower == "course catalog"
            || lower.contains("course descriptions")
            || lower.contains("course listing")
    }

    private static func isCourseDetailURL(_ lower: String) -> Bool {
        lower.contains("preview_course_nopop") || lower.contains("coid=")
    }

    private static func isProgramListingURL(_ lower: String, labelLower: String) -> Bool {
        guard lower.contains("content.php"), lower.contains("navoid=") else { return false }
        let containerHints = [
            "major", "minor", "degree", "program", "department", "school", "college",
            "academic", "undergraduate", "graduate"
        ]
        return containerHints.contains(where: { labelLower.contains($0) })
    }

    /// Ratio of `preview_program` / `preview_entity` anchors to all anchors (0...1).
    static func outboundProgramLinkDensity(in html: String) -> Double {
        guard let doc = try? SwiftSoup.parse(html) else { return 0 }
        let anchors = (try? doc.select("a[href]").array()) ?? []
        guard !anchors.isEmpty else { return 0 }
        var programLinks = 0
        for anchor in anchors {
            let href = ((try? anchor.attr("href")) ?? "").lowercased()
            if href.contains("preview_program") || href.contains("preview_entity") {
                programLinks += 1
            }
        }
        return Double(programLinks) / Double(anchors.count)
    }

    static func reclassifyUnknownPageKind(
        url: String,
        linkLabel: String,
        host: String?,
        listingHTML: String? = nil
    ) -> CatalogPageKind {
        let labelLower = linkLabel.lowercased()
        let synonyms = ModernCampusHostProfiles.navLabelSynonyms(host: host)
        if synonyms.contains(where: { labelLower.contains($0) }) {
            return .programListing
        }
        let lower = url.lowercased()
        if let html = listingHTML?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
            let density = outboundProgramLinkDensity(in: html)
            if density >= 0.15, lower.contains("content.php"), lower.contains("navoid=") {
                return .programListing
            }
        }
        let queryItemsCount = URLComponents(string: url)?.queryItems?.count ?? 0
        let hasProgramHints = lower.contains("content.php") && (lower.contains("navoid=") || lower.contains("preview_entity"))
        let density = hasProgramHints ? min(1.0, Double(queryItemsCount) / 5.0) : 0
        return density >= 0.2 ? .programListing : .unknown
    }

    private static func reclassifyUnknownPageKind(
        url: String,
        linkLabel: String,
        host: String?
    ) -> CatalogPageKind {
        reclassifyUnknownPageKind(url: url, linkLabel: linkLabel, host: host, listingHTML: nil)
    }

    private static func discoverEntityLinkedProgramURLs(
        baseURL: URL,
        catalogs: [ModernCampusCatalogDescriptor],
        sidebarByCatoid: [String: [SidebarEntry]]
    ) async throws -> [String] {
        var discovered = Set<String>()
        let politeness = CatalogFetchPoliteness.catalogSkeleton

        for catalog in catalogs {
            let catoid = catalog.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !catoid.isEmpty else { continue }
            let sidebar = sidebarByCatoid[catoid] ?? []
            let listingURLs = sidebar
                .map(\.url)
                .filter { url in
                    let kind = classifyPageKind(url: url)
                    return kind == .programListing || kind == .unknown
                }
                .prefix(12)

            for listingURL in listingURLs {
                let html = try await ModernCampusEngine.fetchHTMLPublic(listingURL, politeness: politeness)
                let entityURLs = extractAnchors(matching: "preview_entity", from: html, baseURL: baseURL)
                for entityURL in entityURLs {
                    discovered.insert(entityURL)
                    let entityHTML = try await ModernCampusEngine.fetchHTMLPublic(entityURL, politeness: politeness)
                    let programURLs = extractAnchors(matching: "preview_program", from: entityHTML, baseURL: baseURL)
                    for programURL in programURLs {
                        discovered.insert(programURL)
                    }
                }
            }
        }

        return discovered.sorted()
    }

    private static func extractAnchors(matching needle: String, from html: String, baseURL: URL) -> [String] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return [] }
        let anchors = (try? doc.select("a[href*=\(needle)]").array()) ?? []
        var out: [String] = []
        var seen = Set<String>()
        for anchor in anchors {
            let href = ((try? anchor.attr("abs:href")) ?? (try? anchor.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, href.lowercased().contains(needle), seen.insert(href).inserted else { continue }
            out.append(href)
        }
        return out
    }

    private static func computeSignature(from inputs: [String], schoolID: String) -> String {
        let payload = ([schoolID] + inputs.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
