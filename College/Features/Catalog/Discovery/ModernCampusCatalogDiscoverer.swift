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
        let catalogs = try await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalized)
        let posted = ModernCampusCatalogLabels.filterPostedCatalogs(from: catalogs)
        let catalogsToUse = posted.isEmpty ? catalogs : posted
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
        return buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            catalogs: catalogs,
            sidebarByCatoid: sidebarByCatoid,
            extraPageURLs: [],
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
                let kind = classifyPageKind(url: entry.url, linkLabel: entry.label)
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
        let container = (try? doc.select("table.block_n2_links.link_table, table.block_n2_links.links_table").first()) ?? doc
        let primaryAnchors = (try? container.select("div.n2_links a[href]").array()) ?? []
        let fallbackAnchors = (try? doc.select(
            "a[href*='content.php'][href*='navoid='], .block_n2_links a[href*='navoid='], td.block_n2_and_content a[href*='navoid='], a.navbar[href*='navoid=']"
        ).array()) ?? []
        let anchors = primaryAnchors.isEmpty ? fallbackAnchors : primaryAnchors
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

    private static func indexURL(baseURL: URL, catoid: String) -> URL {
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

    private static func computeSignature(from inputs: [String], schoolID: String) -> String {
        let payload = ([schoolID] + inputs.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
