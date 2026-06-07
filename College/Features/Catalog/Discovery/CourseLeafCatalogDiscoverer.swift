// CourseLeafCatalogDiscoverer.swift
// Feature: Catalog
// Purpose: Catalog module — build immutable CatalogGraph from CourseLeaf sitemap URLs.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// Discovery-only CourseLeaf graph builder (no `index.xml` fetches).
enum CourseLeafCatalogDiscoverer {
    private static let engineID = "courseleaf"

    static func buildGraph(
        manifest: SchoolManifest,
        baseURL rawURL: String,
        discoveredAt: Date = Date()
    ) async throws -> CatalogGraph {
        guard let baseURL = CourseLeafEngine.normalizeBaseURL(rawURL) else {
            throw ScraperError.invalidURL
        }
        let pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
        return buildGraph(
            manifest: manifest,
            baseURL: baseURL,
            pageURLs: pageURLs,
            discoveredAt: discoveredAt
        )
    }

    static func buildGraph(
        manifest: SchoolManifest,
        baseURL: URL,
        pageURLs: [URL],
        discoveredAt: Date = Date()
    ) -> CatalogGraph {
        let schoolID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let crawlConfig = CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID)
        let manifestVersion = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
        let onboardingCatalogs = CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
            pageURLs: pageURLs,
            schoolID: schoolID
        )

        var catalogHubByID: [String: CatalogPageNode] = [:]
        var catalogVersionByID: [String: CatalogVersion] = [:]
        for catalog in onboardingCatalogs {
            let version = CatalogVersion.resolve(
                school: manifest,
                segment: .courseLeafOnboarding(catalog)
            )
            catalogVersionByID[catalog.id] = version
            let hubURL = hubURL(baseURL: baseURL, pathPrefixes: catalog.pathPrefixes)
            catalogHubByID[catalog.id] = CatalogPageNode(
                url: hubURL,
                kind: .programListing,
                parentNodeID: nil,
                depth: 0,
                catalogVersionID: version.id,
                discoveryConfidence: 1.0
            )
        }

        var nodes: [CatalogPageNode] = []
        nodes.reserveCapacity(onboardingCatalogs.count + pageURLs.count + 1)

        let indexNode = CatalogPageNode(
            url: baseURL.absoluteString,
            kind: .index,
            parentNodeID: nil,
            depth: 0,
            catalogVersionID: manifestVersion.id,
            discoveryConfidence: 1.0
        )
        nodes.append(indexNode)
        nodes.append(contentsOf: catalogHubByID.values)

        let hubIDByCatalogID = Dictionary(uniqueKeysWithValues: catalogHubByID.map { ($0.key, $0.value.id) })

        for pageURL in pageURLs.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            let urlString = pageURL.absoluteString
            if urlString == indexNode.url { continue }

            let kind = classifyPageKind(path: pageURL.path, config: crawlConfig)
            let matchingCatalog = CourseLeafCatalogSegmentDiscoverer.bestMatchingOnboardingCatalog(
                forProgramURL: urlString,
                in: onboardingCatalogs
            )
            let catalogVersionID: String
            let parentNodeID: UUID?
            let depth: Int
            if let matchingCatalog,
               catalogHubByID[matchingCatalog.id] != nil,
               let hubID = hubIDByCatalogID[matchingCatalog.id] {
                catalogVersionID = catalogVersionByID[matchingCatalog.id]?.id ?? manifestVersion.id
                parentNodeID = hubID
                depth = relativeDepth(pagePath: pageURL.path, catalogPrefixes: matchingCatalog.pathPrefixes)
            } else {
                catalogVersionID = manifestVersion.id
                parentNodeID = nil
                depth = pathDepth(pageURL.path)
            }

            nodes.append(
                CatalogPageNode(
                    url: urlString,
                    kind: kind,
                    parentNodeID: parentNodeID,
                    depth: depth,
                    catalogVersionID: catalogVersionID,
                    discoveryConfidence: kind == .unknown ? 0.5 : 1.0
                )
            )
        }

        let signatureMaterial = nodes.map(\.url).sorted()
        let sourceSignature = computeSignature(from: signatureMaterial, schoolID: schoolID)

        return CatalogGraph(
            schoolID: schoolID,
            catalogVersionID: manifestVersion.id,
            engine: engineID,
            nodes: nodes,
            discoveredAt: discoveredAt,
            sourceSignature: sourceSignature
        )
    }

    static func classifyPageKind(path: String, schoolID: String) -> CatalogPageKind {
        classifyPageKind(path: path, config: CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID))
    }

    private static func classifyPageKind(
        path: String,
        config: CourseLeafProfileConfig
    ) -> CatalogPageKind {
        let lower = path.lowercased()

        if isPolicyPath(lower) {
            return .policy
        }

        if lower.isEmpty || lower == "/" {
            return .index
        }

        if isCourseListingPath(lower) {
            return isCourseDetailPath(lower) ? .courseDetail : .courseListing
        }

        if config.programPagePathHints.contains(where: { lower.contains($0.lowercased()) }) {
            if isProgramDetailPath(lower) {
                return .programDetail
            }
            if isProgramListingPath(lower) {
                return .programListing
            }
            return .programDetail
        }

        if isProgramListingPath(lower) {
            return .programListing
        }

        return .unknown
    }

    private static func hubURL(baseURL: URL, pathPrefixes: [String]) -> String {
        guard let prefix = pathPrefixes.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prefix.isEmpty else {
            return baseURL.absoluteString
        }
        let normalizedPrefix = prefix.hasPrefix("/") ? prefix : "/\(prefix)"
        var base = baseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        return base + normalizedPrefix
    }

    private static func relativeDepth(pagePath: String, catalogPrefixes: [String]) -> Int {
        let lower = pagePath.lowercased()
        let prefixLengths = catalogPrefixes
            .map { $0.lowercased() }
            .compactMap { prefix -> Int? in
                guard lower.contains(prefix) else { return nil }
                return prefix.split(separator: "/").filter { !$0.isEmpty }.count
            }
        let anchor = prefixLengths.max() ?? 0
        let total = pathDepth(pagePath)
        return max(0, total - anchor)
    }

    private static func pathDepth(_ path: String) -> Int {
        path
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .count
    }

    private static func isPolicyPath(_ lower: String) -> Bool {
        let hints = [
            "/policies",
            "policies-procedures",
            "academic-policies",
            "attribute-codes",
            "instructional-modalities"
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func isCourseListingPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/courses/")
            || lower.contains("course-descriptions")
            || lower.contains("coursedescriptions")
    }

    private static func isCourseDetailPath(_ lower: String) -> Bool {
        guard isCourseListingPath(lower) else { return false }
        let parts = lower.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if let coursesIndex = parts.firstIndex(where: { $0 == "courses" }),
           coursesIndex + 2 < parts.count {
            return true
        }
        if lower.contains("course-descriptions") || lower.contains("coursedescriptions") {
            return parts.count >= 4
        }
        return false
    }

    private static func isProgramListingPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if isCourseListingPath(lower) {
            return false
        }
        if isProgramDetailPath(lower) {
            return false
        }
        let collegeCatalogRoots = [
            "/undergraduate/", "/graduate/", "/schools-colleges/", "/gabelli-graduate/",
            "/gsas/", "/gse/", "/gss/", "/pcs-grad/"
        ]
        return collegeCatalogRoots.contains(where: { lower.contains($0) })
    }

    private static func isProgramDetailPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let hints = [
            "/major/", "/minor/", "/programs/", "/program/", "/degree/", "/mba/", "/ms/", "/doctoral/"
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func computeSignature(from inputs: [String], schoolID: String) -> String {
        let payload = ([schoolID] + inputs.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
