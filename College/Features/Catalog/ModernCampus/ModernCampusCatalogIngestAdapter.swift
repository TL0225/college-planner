// ModernCampusCatalogIngestAdapter.swift
// Feature: Catalog
// Purpose: Modern Campus Document IR crawl — graph pages → programs/courses.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum ModernCampusCatalogIngestAdapter {
    struct ProgramRowMetadata: Sendable {
        let layoutProfileID: String
        let layoutConfidence: Double
        let provenance: CatalogProvenance
    }

    struct ScrapeResult: Sendable {
        let programs: [ScrapedProgram]
        let courses: [CatalogCourse]
        let dominantLayoutProfileID: String?
        let metadataByProgramURL: [String: ProgramRowMetadata]
        let documentIR: CatalogDocumentIR?
    }

    /// Crawls `graph` extractable URLs for one catalog catoid and merges IR extraction output.
    static func scrapeProgramsViaIR(
        graph: CatalogGraph,
        manifest: SchoolManifest,
        catalog: ModernCampusCatalogDescriptor,
        programsIndexOnly: Bool,
        politeness: CatalogFetchPoliteness = .interactiveBackground
    ) async throws -> ScrapeResult {
        let catoid = catalog.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catoid.isEmpty else {
            return ScrapeResult(
                programs: [],
                courses: [],
                dominantLayoutProfileID: nil,
                metadataByProgramURL: [:],
                documentIR: nil
            )
        }

        // Use discovery-time node kinds (sidebar labels); re-classifying content.php URLs without
        // labels incorrectly drops program listing pages (DSU, Stony Brook, etc.).
        let pageURLs = graph.nodes
            .filter { node in
                let matchesCatoid = node.url.contains("catoid=\(catoid)") || node.url.contains("catoid%3D\(catoid)")
                guard matchesCatoid else { return false }
                if programsIndexOnly {
                    return node.kind == .programListing || node.kind == .programDetail
                }
                return [.programDetail, .courseListing, .courseDetail, .programListing].contains(node.kind)
            }
            .map(\.url)
            .sorted()
        guard !pageURLs.isEmpty else {
            return ScrapeResult(
                programs: [],
                courses: [],
                dominantLayoutProfileID: nil,
                metadataByProgramURL: [:],
                documentIR: nil
            )
        }

        let version = CatalogVersion.resolve(school: manifest, segment: .modernCampus(catalog))
        let ingestRunID = UUID()
        let schoolID = manifest.id
        let pageFetchCache = ModernCampusPageFetchCache()
        var programsByURL: [String: ScrapedProgram] = [:]
        var coursesByCode: [String: CatalogCourse] = [:]
        var metadataByURL: [String: ProgramRowMetadata] = [:]
        var profileCounts: [String: Int] = [:]
        var accumulatedIRNodes: [CatalogDocumentNode] = []

        let crawlDelay: TimeInterval
        if let catalogURL = URL(string: (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
            crawlDelay = await CatalogOriginRobotsThrottle.declaredCrawlDelaySeconds(for: catalogURL)
        } else {
            crawlDelay = 0
        }
        let irConcurrency = ModernCampusEngine.effectiveConcurrency(declaredCrawlDelay: crawlDelay, max: 4)
        let semaphore = ModernCampusEngine.AsyncSemaphore(value: irConcurrency)
        try await withThrowingTaskGroup(of: (String, ModernCampusIRPipeline.PageParseResult).self) { group in
            for rawURL in pageURLs {
                let pageURLString = rawURL
                group.addTask {
                    await semaphore.acquire()
                    defer { semaphore.release() }
                    try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
                    guard let pageURL = URL(string: pageURLString) else {
                        throw ScraperError.invalidURL
                    }
                    let html = try await pageFetchCache.fetchHTML(pageURLString, politeness: politeness)
                    let parsed = await ModernCampusIRPipeline.parsePageAsync(
                        html: html,
                        pageURL: pageURL,
                        schoolID: schoolID,
                        catalogVersionID: version.id
                    )
                    return (pageURLString, parsed)
                }
            }

            for try await (pageURLString, parsed) in group {
                let profileID = parsed.ir.layoutProfileID
                profileCounts[profileID, default: 0] += 1
                UniversalCatalogScraperIRConsumer.mergeNodes(parsed.ir.nodes, into: &accumulatedIRNodes)

                for program in parsed.programs {
                    let normalizedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    let dedupKey = canonicalProgramDedupKey(url: normalizedURL, fallbackName: program.name)
                    guard !dedupKey.isEmpty else { continue }
                    programsByURL[dedupKey] = program

                    let documentNodeID = parsed.ir.nodes.first(where: { ($0.sourceURL ?? "").contains("preview_program") })?.id ?? parsed.ir.nodes.first?.id ?? UUID()
                    let provenance = CatalogProvenance(
                        sourceURL: normalizedURL.isEmpty ? pageURLString : normalizedURL,
                        layoutProfileID: profileID,
                        documentNodeID: documentNodeID,
                        catalogVersionID: version.id,
                        extractedAt: Date(),
                        ingestRunID: ingestRunID
                    )
                    metadataByURL[dedupKey] = ProgramRowMetadata(
                        layoutProfileID: profileID,
                        layoutConfidence: parsed.ir.layoutConfidence.score,
                        provenance: provenance
                    )
                }

                for course in parsed.courses {
                    let enriched = CatalogExternalReferenceBuilder.enriching(
                        course,
                        engine: "moderncampus",
                        schoolID: schoolID
                    )
                    let code = enriched.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty else { continue }
                    if coursesByCode[code] == nil {
                        coursesByCode[code] = enriched
                    }
                }

                if !programsIndexOnly, parsed.ir.layoutProfileID == ModernCampusLayoutProfileID.entityPreviewProgram.rawValue {
                    let bfsPrograms = try await extractEntityPageProgramsBFS(
                        from: parsed.ir,
                        schoolID: schoolID,
                        catalogVersionID: version.id,
                        pageFetchCache: pageFetchCache,
                        politeness: politeness
                    )
                    for program in bfsPrograms {
                        let dedupKey = canonicalProgramDedupKey(url: program.url, fallbackName: program.name)
                        guard !dedupKey.isEmpty else { continue }
                        programsByURL[dedupKey] = program
                    }
                }
            }
        }

        if shouldFallbackToUniversalScraper(
            irProgramCount: programsByURL.count,
            host: URL(string: manifest.catalogURL ?? "")?.host
        ),
        let fallbackIR = await UniversalCatalogScraperIRConsumer.buildDocumentIR(
            graph: graph,
            schoolID: schoolID,
            catalogVersionID: version.id,
            layoutProfileID: "moderncampus-ir-fallback",
            catoid: catoid,
            maxPages: 12,
            programsIndexOnly: true,
            politeness: politeness,
            pageFetchCache: pageFetchCache
        ) {
            UniversalCatalogScraperIRConsumer.mergeNodes(fallbackIR.nodes, into: &accumulatedIRNodes)
            let fallbackPrograms = ModernCampusLayoutProfileID
                .entityPreviewProgram
                .extractEntities(
                    from: fallbackIR,
                    pageURL: URL(string: manifest.catalogURL ?? "") ?? URL(fileURLWithPath: "/"),
                    config: ModernCampusProfileConfig.forHost(URL(string: manifest.catalogURL ?? "")?.host)
                )
                .programs
            for program in fallbackPrograms {
                let dedupKey = canonicalProgramDedupKey(url: program.url, fallbackName: program.name)
                guard !dedupKey.isEmpty else { continue }
                programsByURL[dedupKey] = program
            }
        }

        let dominantProfile = profileCounts.max(by: { $0.value < $1.value })?.key
        let documentIR = UniversalCatalogScraperIRConsumer.buildDocumentIR(
            schoolID: schoolID,
            catalogVersionID: version.id,
            nodes: accumulatedIRNodes,
            layoutProfileID: dominantProfile ?? "moderncampus-ir"
        )
        return ScrapeResult(
            programs: Array(programsByURL.values),
            courses: Array(coursesByCode.values),
            dominantLayoutProfileID: dominantProfile,
            metadataByProgramURL: metadataByURL,
            documentIR: documentIR
        )
    }

    static func persistDocumentIRIfNeeded(
        manifest: SchoolManifest,
        catalog: ModernCampusCatalogDescriptor,
        graph: CatalogGraph?,
        scraper: UniversalCatalogScraper,
        irScrapeResult: ScrapeResult?,
        layoutProfileID: String?,
        programsIndexOnly: Bool = false,
        politeness: CatalogFetchPoliteness = .interactiveBackground
    ) async {
        guard CatalogPlatformFlags.documentIREnabled else { return }
        let version = CatalogVersion.resolve(
            school: manifest,
            segment: .modernCampus(catalog)
        )
        var nodes: [CatalogDocumentNode] = []
        if let irNodes = irScrapeResult?.documentIR?.nodes {
            UniversalCatalogScraperIRConsumer.mergeNodes(irNodes, into: &nodes)
        }
        if let graph,
           let graphIR = await UniversalCatalogScraperIRConsumer.buildDocumentIR(
               graph: graph,
               schoolID: manifest.id,
               catalogVersionID: version.id,
               layoutProfileID: layoutProfileID ?? "moderncampus-graph",
               catoid: catalog.catoid,
               programsIndexOnly: programsIndexOnly,
               politeness: politeness,
               pageFetchCache: ModernCampusPageFetchCache()
           ) {
            UniversalCatalogScraperIRConsumer.mergeNodes(graphIR.nodes, into: &nodes)
        }
        if let streamIR = await scraper.lastDocumentIR(
            layoutProfileID: layoutProfileID ?? "universal-scraper"
        ) {
            UniversalCatalogScraperIRConsumer.mergeNodes(streamIR.nodes, into: &nodes)
        }
        guard let ir = UniversalCatalogScraperIRConsumer.buildDocumentIR(
            schoolID: manifest.id,
            catalogVersionID: version.id,
            nodes: nodes,
            layoutProfileID: layoutProfileID ?? "moderncampus"
        ) else { return }
        CatalogDocumentIRStore.save(ir, schoolID: manifest.id, catalogVersionID: version.id)
    }

    /// When IR extraction returns too few programs for hosts that rely on entity-page discovery, use the legacy scraper.
    static func shouldFallbackToUniversalScraper(
        irProgramCount: Int,
        host: String?,
        minimumPrograms: Int = 3
    ) -> Bool {
        let config = ModernCampusProfileConfig.forHost(host)
        if config.prefersEntityPageProgramDiscovery, irProgramCount < minimumPrograms {
            return true
        }
        return irProgramCount == 0
    }

    /// When IR course stubs are sparse, Phase B should run the legacy course stream (always true below threshold).
    static func shouldFallbackToUniversalScraperForCourses(
        irCourseCount: Int,
        minimumCourses: Int = 25
    ) -> Bool {
        irCourseCount < minimumCourses
    }

    static func mergeCourses(
        primary: [CatalogCourse],
        irFallback: [CatalogCourse]
    ) -> [CatalogCourse] {
        guard !irFallback.isEmpty else { return primary }
        if primary.isEmpty { return irFallback }
        var byCode: [String: CatalogCourse] = [:]
        for course in primary {
            let code = CatalogImportTransforms.normalizeCourseCode(course.courseCode)
            guard !code.isEmpty else { continue }
            byCode[code] = course
        }
        for course in irFallback {
            let code = CatalogImportTransforms.normalizeCourseCode(course.courseCode)
            guard !code.isEmpty, byCode[code] == nil else { continue }
            byCode[code] = course
        }
        return Array(byCode.values).sorted { $0.courseCode < $1.courseCode }
    }
}

extension CatalogProvenance {
    func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension ModernCampusCatalogIngestAdapter {
    private static func canonicalProgramDedupKey(url: String, fallbackName: String) -> String {
        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.isEmpty {
            return canonicalURL(normalizedURL)
        }
        return fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func extractEntityPageProgramsBFS(
        from ir: CatalogDocumentIR,
        schoolID: String,
        catalogVersionID: String,
        pageFetchCache: ModernCampusPageFetchCache,
        politeness: CatalogFetchPoliteness
    ) async throws -> [ScrapedProgram] {
        let seedURLs = ir.nodes
            .compactMap(\.sourceURL)
            .filter { $0.contains("preview_entity") }
        guard !seedURLs.isEmpty else { return [] }

        var queue = Array(seedURLs.prefix(16))
        var seen = Set<String>()
        var programsByKey: [String: ScrapedProgram] = [:]

        while !queue.isEmpty, programsByKey.count < 2_000 {
            try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
            let raw = queue.removeFirst()
            let canonical = canonicalURL(raw)
            guard seen.insert(canonical).inserted else { continue }
            guard let pageURL = URL(string: raw) else { continue }
            let html = try await pageFetchCache.fetchHTML(raw, politeness: politeness)
            let parsed = await ModernCampusIRPipeline.parsePageAsync(
                html: html,
                pageURL: pageURL,
                schoolID: schoolID,
                catalogVersionID: catalogVersionID
            )
            let extracted = ModernCampusLayoutProfileID
                .entityPreviewProgram
                .extractEntities(
                    from: parsed.ir,
                    pageURL: pageURL,
                    config: ModernCampusProfileConfig.forHost(pageURL.host)
                )
            for program in extracted.programs {
                let key = canonicalProgramDedupKey(url: program.url, fallbackName: program.name)
                guard !key.isEmpty else { continue }
                programsByKey[key] = program
            }
        }

        return Array(programsByKey.values)
    }

    private static func canonicalURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        let filtered = (components.queryItems ?? [])
            .filter { $0.name.lowercased() != "returnto" }
            .sorted {
                if $0.name.lowercased() == $1.name.lowercased() {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name.lowercased() < $1.name.lowercased()
            }
        components.queryItems = filtered.isEmpty ? nil : filtered
        components.fragment = nil
        return components.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    }
}
