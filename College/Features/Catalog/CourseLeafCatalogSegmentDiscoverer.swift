// CourseLeafCatalogSegmentDiscoverer.swift
// Feature: Catalog
// Purpose: Catalog module — OnboardingCatalog.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Discovers catalog segment prefixes from a CourseLeaf sitemap so live contract tests
/// can cover every school/college/department slice instead of a hand-picked subset.
enum CourseLeafCatalogSegmentDiscoverer {
    /// Top-level bulletin catalogs shown during onboarding (not per-department sitemap slices).
    struct OnboardingCatalog: Sendable, Equatable {
        let id: String
        let displayName: String
        let pathPrefixes: [String]
    }

    struct DiscoveredSegment: Sendable, Equatable {
        let id: String
        let displayName: String
        let pathPrefix: String
        let minCourses: Int
        let minPrograms: Int
    }

    private struct OnboardingCatalogTemplate {
        let key: String
        let displayName: String
        let pathPrefixes: [String]
    }

    private struct SchoolDiscoveryConfig {
        let catalogRoots: [String]
        let segmentDepth: Int
        let minSitemapURLs: Int
    }

    private static let configs: [String: SchoolDiscoveryConfig] = [
        "fordham_university": SchoolDiscoveryConfig(
            catalogRoots: [
                "undergraduate", "courses", "gabelli-graduate", "gsas", "gse", "gss", "pcs-grad"
            ],
            segmentDepth: 2,
            minSitemapURLs: 1
        ),
        "carnegie_mellon_university": SchoolDiscoveryConfig(
            catalogRoots: ["schools-colleges"],
            segmentDepth: 2,
            minSitemapURLs: 1
        ),
        "new_york_university": SchoolDiscoveryConfig(
            catalogRoots: ["undergraduate", "graduate", "courses"],
            segmentDepth: 2,
            minSitemapURLs: 1
        )
    ]

    private static let excludedPathComponents: Set<String> = [
        "resources",
        "policies-procedures",
        "academic-policies-procedures",
        "academic-policies",
        "attribute-codes",
        "special-academic-programs",
        "academic-areas",
        "concentrations",
        "degreesoffered",
        "aboutcmu",
        "catalogfaqs",
        "coursedescriptions",
        "programs-old",
        "oapraadmin",
        "class-search",
        "student-services",
        "policies",
        "group-prerequisites",
        "instructional-modalities-at-university",
        "sam",
        "workflow.html"
    ]

    static func discoverSegments(baseURL rawURL: String, schoolID: String) async throws -> [DiscoveredSegment] {
        guard let baseURL = CourseLeafEngine.normalizeBaseURL(rawURL) else {
            throw ScraperError.invalidURL
        }
        let pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
        return discoverSegments(pageURLs: pageURLs, schoolID: schoolID)
    }

    /// Segments that contain program listings (excludes course-only dept buckets like `/courses/aast/`).
    static func onboardingProgramSegments(pageURLs: [URL], schoolID: String) -> [DiscoveredSegment] {
        discoverSegments(pageURLs: pageURLs, schoolID: schoolID)
            .filter { $0.minPrograms > 0 }
    }

    static func onboardingProgramSegments(baseURL rawURL: String, schoolID: String) async throws -> [DiscoveredSegment] {
        guard let baseURL = CourseLeafEngine.normalizeBaseURL(rawURL) else {
            throw ScraperError.invalidURL
        }
        let pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
        return onboardingProgramSegments(pageURLs: pageURLs, schoolID: schoolID)
    }

    /// School-specific top-level catalogs for onboarding UI and skeleton program indexing.
    static func onboardingCatalogs(pageURLs: [URL], schoolID: String) -> [OnboardingCatalog] {
        onboardingCatalogTemplates(for: schoolID).compactMap { template in
            let hasContent = pageURLs.contains { url in
                programMatchesCatalog(url: url.path, catalogPrefixes: template.pathPrefixes)
            }
            guard hasContent else { return nil }
            return OnboardingCatalog(
                id: onboardingCatalogID(schoolID: schoolID, key: template.key),
                displayName: template.displayName,
                pathPrefixes: template.pathPrefixes
            )
        }
    }

    static func onboardingCatalogs(baseURL rawURL: String, schoolID: String) async throws -> [OnboardingCatalog] {
        guard let baseURL = CourseLeafEngine.normalizeBaseURL(rawURL) else {
            throw ScraperError.invalidURL
        }
        let pageURLs = try await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL)
        return onboardingCatalogs(pageURLs: pageURLs, schoolID: schoolID)
    }

    static func catalogDescriptors(from catalogs: [OnboardingCatalog]) -> [ModernCampusCatalogDescriptor] {
        catalogs.map { catalog in
            ModernCampusCatalogDescriptor(catoid: catalog.id, title: catalog.displayName)
        }
    }

    static func catalogDescriptors(from segments: [DiscoveredSegment]) -> [ModernCampusCatalogDescriptor] {
        segments.map { segment in
            ModernCampusCatalogDescriptor(catoid: segment.id, title: segment.displayName)
        }
    }

    static func programMatchesCatalog(url: String, catalog: OnboardingCatalog) -> Bool {
        programMatchesCatalog(url: url, catalogPrefixes: catalog.pathPrefixes)
    }

    /// Path prefixes for an onboarding catalog id (e.g. `new_york_university_undergraduate` → `/undergraduate/`).
    static func pathPrefixes(forCatalogID catoid: String) -> [String] {
        let token = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return [] }

        let schoolIDs = configs.keys.sorted { $0.count > $1.count }
        for schoolID in schoolIDs {
            let lead = "\(schoolID)_"
            guard token.hasPrefix(lead) else { continue }
            let key = String(token.dropFirst(lead.count))
            guard let template = onboardingCatalogTemplates(for: schoolID).first(where: { $0.key == key }) else {
                continue
            }
            return template.pathPrefixes
        }
        return []
    }

    /// Whether a stored program URL belongs to the catalog identified by `catoid`.
    static func programURLMatchesCatalogID(_ programURL: String, catalogID: String) -> Bool {
        let trimmedURL = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return false }
        let lower = trimmedURL.lowercased()
        return pathPrefixes(forCatalogID: catalogID).contains { prefix in
            let normalized = prefix.lowercased()
            return lower.contains(normalized)
        }
    }

    static func bestMatchingOnboardingCatalog(
        forProgramURL url: String,
        in catalogs: [OnboardingCatalog]
    ) -> OnboardingCatalog? {
        let matches = catalogs.filter { programMatchesCatalog(url: url, catalog: $0) }
        return matches.max(by: { lhs, rhs in
            let lhsDepth = lhs.pathPrefixes.map(\.count).max() ?? 0
            let rhsDepth = rhs.pathPrefixes.map(\.count).max() ?? 0
            return lhsDepth < rhsDepth
        })
    }

    static func bestMatchingSegment(forProgramURL url: String, in segments: [DiscoveredSegment]) -> DiscoveredSegment? {
        let lower = url.lowercased()
        return segments
            .filter { lower.contains($0.pathPrefix.lowercased()) }
            .max(by: { $0.pathPrefix.count < $1.pathPrefix.count })
    }

    private static func onboardingCatalogTemplates(for schoolID: String) -> [OnboardingCatalogTemplate] {
        switch schoolID {
        case "new_york_university":
            return [
                OnboardingCatalogTemplate(
                    key: "undergraduate",
                    displayName: "Undergraduate",
                    pathPrefixes: ["/undergraduate/"]
                ),
                OnboardingCatalogTemplate(
                    key: "graduate",
                    displayName: "Graduate",
                    pathPrefixes: ["/graduate/"]
                )
            ]
        case "fordham_university":
            return [
                OnboardingCatalogTemplate(
                    key: "undergraduate",
                    displayName: "Undergraduate",
                    pathPrefixes: ["/undergraduate/"]
                ),
                OnboardingCatalogTemplate(
                    key: "gabelli_graduate",
                    displayName: "Graduate School of Business",
                    pathPrefixes: ["/gabelli-graduate/"]
                ),
                OnboardingCatalogTemplate(
                    key: "gsas",
                    displayName: "Graduate School of Arts and Sciences",
                    pathPrefixes: ["/gsas/"]
                ),
                OnboardingCatalogTemplate(
                    key: "gse",
                    displayName: "Graduate School of Education",
                    pathPrefixes: ["/gse/"]
                ),
                OnboardingCatalogTemplate(
                    key: "gss",
                    displayName: "Graduate School of Social Service",
                    pathPrefixes: ["/gss/"]
                ),
                OnboardingCatalogTemplate(
                    key: "pcs_grad",
                    displayName: "School of Professional and Continuing Studies",
                    pathPrefixes: ["/pcs-grad/"]
                )
            ]
        case "carnegie_mellon_university":
            return [
                OnboardingCatalogTemplate(
                    key: "university_catalog",
                    displayName: "University Catalog",
                    pathPrefixes: ["/schools-colleges/", "/intercollegeprograms/"]
                )
            ]
        default:
            return []
        }
    }

    private static func onboardingCatalogID(schoolID: String, key: String) -> String {
        "\(schoolID)_\(key)"
    }

    private static func programMatchesCatalog(url: String, catalogPrefixes: [String]) -> Bool {
        let lower = url.lowercased()
        return catalogPrefixes.contains { lower.contains($0.lowercased()) }
    }

    static func discoverSegments(pageURLs: [URL], schoolID: String) -> [DiscoveredSegment] {
        guard let config = configs[schoolID] else { return [] }

        var buckets: [String: [URL]] = [:]
        for url in pageURLs {
            let parts = url.path
                .split(separator: "/")
                .map { String($0).lowercased() }
                .filter { !$0.isEmpty }
            guard let root = parts.first, config.catalogRoots.contains(root) else { continue }
            if parts.contains(where: { excludedPathComponents.contains($0) }) { continue }

            let depth = min(config.segmentDepth, parts.count)
            guard depth > 0 else { continue }
            let prefix = "/" + parts.prefix(depth).joined(separator: "/") + "/"
            buckets[prefix, default: []].append(url)
        }

        return buckets
            .filter { $0.value.count >= config.minSitemapURLs }
            .map { prefix, urls in
                let hasCoursePages = urls.contains { isCourseListingPath($0.path) }
                let hasProgramPages = urls.contains { isProgramListingPath($0.path) }
                return DiscoveredSegment(
                    id: segmentID(schoolID: schoolID, pathPrefix: prefix),
                    displayName: displayName(for: prefix),
                    pathPrefix: prefix,
                    minCourses: hasCoursePages ? 1 : 0,
                    minPrograms: hasProgramPages ? 1 : 0
                )
            }
            .sorted { $0.pathPrefix < $1.pathPrefix }
    }

    private static func isCourseListingPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/courses/")
            || lower.contains("course-descriptions")
            || lower.contains("coursedescriptions")
    }

    private static func isProgramListingPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if isCourseListingPath(lower) {
            return false
        }
        if isStrictProgramListingPath(lower) {
            return true
        }
        let collegeCatalogRoots = [
            "/undergraduate/", "/graduate/", "/schools-colleges/", "/gabelli-graduate/",
            "/gsas/", "/gse/", "/gss/", "/pcs-grad/"
        ]
        return collegeCatalogRoots.contains(where: { lower.contains($0) })
    }

    private static func isStrictProgramListingPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let hints = [
            "/major/", "/minor/", "/programs/", "/program/", "/degree/", "/mba/", "/ms/", "/doctoral/"
        ]
        return hints.contains(where: { lower.contains($0) })
    }

    private static func segmentID(schoolID: String, pathPrefix: String) -> String {
        let slug = pathPrefix
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        return "\(schoolID)_\(slug)"
    }

    private static func displayName(for pathPrefix: String) -> String {
        pathPrefix
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map { part in
                part
                    .replacingOccurrences(of: "-", with: " ")
                    .split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
            }
            .joined(separator: " / ")
    }
}
