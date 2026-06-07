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
        programsIndexOnly: Bool
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

        let version = CatalogVersion.resolve(school: manifest, segment: .modernCampus(catalog))
        let pageURLs = graph.extractablePageURLs.filter { url in
            url.contains("catoid=\(catoid)") || url.contains("catoid%3D\(catoid)")
        }
        guard !pageURLs.isEmpty else {
            return ScrapeResult(
                programs: [],
                courses: [],
                dominantLayoutProfileID: nil,
                metadataByProgramURL: [:],
                documentIR: nil
            )
        }

        let ingestRunID = UUID()
        let schoolID = manifest.id
        var programsByURL: [String: ScrapedProgram] = [:]
        var coursesByCode: [String: CatalogCourse] = [:]
        var metadataByURL: [String: ProgramRowMetadata] = [:]
        var profileCounts: [String: Int] = [:]
        var accumulatedIRNodes: [CatalogDocumentNode] = []

        let semaphore = ModernCampusEngine.AsyncSemaphore(value: 4)
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
                    let html = try await ModernCampusEngine.fetchHTMLPublic(pageURLString)
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
                    let dedupKey = normalizedURL.isEmpty ? program.name : normalizedURL
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
                    _ = pageURLString
                }
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
        layoutProfileID: String?
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
               catoid: catalog.catoid
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
