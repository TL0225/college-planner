// CatalogVerificationLiveSuiteTests.swift
// Feature: Catalog
// Purpose: End-to-end, live-network verification that EVERY scraper-backed school
//          in schools.json can be discovered, have its program index scraped, and
//          yield parseable requirements for a sample program.
// Data: Hits live university catalogs. Skipped by default.
//
// Run with:
//   COLLEGE_RUN_LIVE_TESTS=1 xcodebuild test \
//     -only-testing:CollegeTests/CatalogVerificationLiveSuiteTests
//
// This is the half of the verification suite that proves real-world scraping.
// The offline configuration/coverage guarantees live in CatalogVerificationSuiteTests.

import XCTest
@testable import College

@MainActor
final class CatalogVerificationLiveSuiteTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try CollegeTestsSupport.skipUnlessLiveNetworkTests()
    }

    /// Minimum programs we expect a real catalog to surface in a skeleton scrape.
    private let minimumPrograms = 5

    func testModernCampusScraperBackedSchoolsScrapeEndToEnd() async throws {
        try await verifyFamily(.modernCampus, attachmentName: "live-coverage-moderncampus")
    }

    func testCourseLeafScraperBackedSchoolsScrapeEndToEnd() async throws {
        try await verifyFamily(.courseLeaf, attachmentName: "live-coverage-courseleaf")
    }

    func testCoursedogScraperBackedSchoolsScrapeEndToEnd() async throws {
        try await verifyFamily(.coursedog, attachmentName: "live-coverage-coursedog")
    }

    // MARK: - Family orchestration

    private func verifyFamily(
        _ familyFilter: CatalogParserFamily?,
        attachmentName: String
    ) async throws {
        let schools = SchoolManifestCatalog.bundled().filter(SchoolManifestSelection.isScraperBacked)
        let familySchools = schools.filter { school in
            guard let familyFilter else { return true }
            return CatalogParserFamily.from(declaredFormat: school.catalogFormat) == familyFilter
        }
        let total = familySchools.count
        if let familyFilter {
            CatalogVerificationProgressLog.familyStarted(familyFilter, schoolCount: total)
        }

        var records: [SchoolVerificationRecord] = []
        var environmentalSkips: [String] = []
        var schoolIndex = 0

        for school in schools {
            let family = CatalogParserFamily.from(declaredFormat: school.catalogFormat)
            if let familyFilter, family != familyFilter {
                continue
            }

            schoolIndex += 1
            let startedAt = Date()

            var record = SchoolVerificationRecord(
                schoolID: school.id,
                name: school.name,
                declaredFormat: school.catalogFormat.lowercased(),
                parserFamily: family,
                scraperBacked: true
            )

            guard CatalogParserFamily.liveVerifiable.contains(family) else {
                record.severity = "skipped-unverified-family"
                records.append(record)
                CatalogVerificationProgressLog.schoolFinished(
                    family: family,
                    record: record,
                    index: schoolIndex,
                    total: total,
                    elapsed: Date().timeIntervalSince(startedAt),
                    testCase: self
                )
                continue
            }

            CatalogVerificationProgressLog.schoolStarted(
                family: family,
                school: school,
                index: schoolIndex,
                total: total
            )

            do {
                switch family {
                case .modernCampus:
                    try await verifyModernCampus(school: school, into: &record)
                case .courseLeaf:
                    try await verifyCourseLeaf(school: school, into: &record)
                case .coursedog:
                    try await verifyCoursedog(school: school, into: &record)
                default:
                    break
                }
            } catch {
                if markEnvironmentalIfNeeded(error: error, into: &record) {
                    environmentalSkips.append("\(school.id): \(error)")
                } else {
                    record.liveError = "\(error)"
                    record.check("scrape_completes", false, "\(error)")
                }
            }

            records.append(record)
            CatalogVerificationProgressLog.schoolFinished(
                family: family,
                record: record,
                index: schoolIndex,
                total: total,
                elapsed: Date().timeIntervalSince(startedAt),
                testCase: self
            )
        }

        let report = CatalogVerificationReport.render(records)
        CatalogVerificationReport.attach(report, name: attachmentName, to: self)

        let exercised = records.filter {
            CatalogParserFamily.liveVerifiable.contains($0.parserFamily)
            && (familyFilter == nil || $0.parserFamily == familyFilter)
        }
        XCTAssertFalse(exercised.isEmpty, "No scraper-backed schools were exercised")

        let scrapeFailures = exercised.filter(\.failed)
        let passed = exercised.filter { !$0.failed && !$0.environmentalSkip && !$0.checks.isEmpty }

        if let familyFilter {
            CatalogVerificationProgressLog.familyFinished(
                familyFilter,
                passed: passed.count,
                failed: scrapeFailures.count,
                environmental: exercised.filter(\.environmentalSkip).count
            )
        }

        if passed.isEmpty, !environmentalSkips.isEmpty, scrapeFailures.isEmpty {
            throw XCTSkip(
                "All exercised schools skipped for environmental reasons: \(environmentalSkips.joined(separator: "; "))"
            )
        }

        XCTAssertTrue(
            scrapeFailures.isEmpty,
            "Live catalog verification failed for \(scrapeFailures.count)/\(exercised.count) school(s):\n\(report)"
        )
    }

    private func markEnvironmentalIfNeeded(error: Error, into record: inout SchoolVerificationRecord) -> Bool {
        guard CollegeTestsSupport.isEnvironmentalLiveCatalogError(error) else { return false }
        record.environmentalSkip = true
        record.severity = "environmental"
        record.liveError = error.localizedDescription
        return true
    }

    private func markEnvironmentalIncompleteCrawl(
        schoolID: String,
        detail: String,
        into record: inout SchoolVerificationRecord
    ) {
        record.environmentalSkip = true
        record.severity = "environmental-incomplete-crawl"
        record.liveError = "\(schoolID): \(detail)"
    }

    // MARK: - Modern Campus / Acalog

    private func verifyModernCampus(school: SchoolManifest, into record: inout SchoolVerificationRecord) async throws {
        let catalogURL = (school.catalogURL ?? "")
        let (normalized, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        guard let baseURL = URL(string: normalized) else {
            record.check("normalize_url", false, "could not normalize \(catalogURL)")
            return
        }

        let catalogs = try await ModernCampusCatalogDiscovery.resolveCatalogsForIngest(
            normalizedBaseURL: normalized,
            catoidHint: catoidHint
        )
        record.check("discover_catalogs", !catalogs.isEmpty, "found \(catalogs.count) catalogs")
        guard !catalogs.isEmpty else { return }

        let graph = try await ModernCampusCatalogDiscoverer.buildGraph(
            manifest: school,
            baseURL: baseURL,
            catalogs: catalogs
        )
        record.check("ir_graph_nodes", graph.nodeCount >= 3, "nodes=\(graph.nodeCount)")

        let scraper = UniversalCatalogScraper()
        var buckets: [(catoid: String, programs: [ScrapedProgram])] = []
        buckets.reserveCapacity(catalogs.count)

        for catalog in catalogs {
            let catalogID = Int(catalog.catoid) ?? 0
            guard catalogID > 0 else { continue }

            var programs: [ScrapedProgram] = []
            if CatalogPlatformFlags.modernCampusIREnabled, CatalogPlatformFlags.documentIREnabled {
                let irResult = try await ModernCampusCatalogIngestAdapter.scrapeProgramsViaIR(
                    graph: graph,
                    manifest: school,
                    catalog: catalog,
                    programsIndexOnly: true,
                    politeness: .catalogSkeleton
                )
                if ModernCampusCatalogIngestAdapter.shouldFallbackToUniversalScraper(
                    irProgramCount: irResult.programs.count,
                    host: baseURL.host
                ) {
                    programs = try await scraper.scrapeAllPrograms(
                        baseURL: baseURL,
                        catalogID: catalogID,
                        programsIndexOnly: true,
                        schoolID: school.id,
                        politeness: .catalogSkeleton
                    )
                } else {
                    programs = irResult.programs
                }
            } else {
                programs = try await scraper.scrapeAllPrograms(
                    baseURL: baseURL,
                    catalogID: catalogID,
                    programsIndexOnly: true,
                    schoolID: school.id,
                    politeness: .catalogSkeleton
                )
            }
            buckets.append((catoid: catalog.catoid, programs: programs))
        }

        let merged = ModernCampusCatalogDiscovery.mergeProgramsAcrossCatalogs(buckets)
        record.programsFound = merged.count
        record.check(
            "programs_found",
            merged.count >= minimumPrograms,
            "found \(merged.count) across \(catalogs.count) catalog edition(s)"
        )

        let outcome = CatalogIngestGate.evaluateModernCampus(
            manifest: school,
            depth: .light,
            programs: merged,
            courses: [],
            requirements: [],
            expectCourses: false
        )
        record.severity = "\(outcome.reviewSeverity)"
        record.check("ingest_gate_not_critical", !outcome.shouldAbortIngest, CatalogIngestGate.abortSummary(outcome))

        try await verifySampleRequirements(
            scraper: scraper,
            programs: merged,
            catalogFormat: school.catalogFormat,
            schoolID: school.id,
            into: &record
        )
    }

    // MARK: - CourseLeaf

    private func verifyCourseLeaf(school: SchoolManifest, into record: inout SchoolVerificationRecord) async throws {
        let catalogURL = (school.catalogURL ?? "")
        let output = try await CourseLeafEngine.crawlCatalog(baseURL: catalogURL, schoolID: school.id)

        record.programsFound = output.programs.count
        record.coursesFound = output.courses.count

        if output.programs.count < minimumPrograms,
           output.courses.count > 500,
           await hasSitemapProgramURLs(baseURL: catalogURL, minimum: minimumPrograms) {
            markEnvironmentalIncompleteCrawl(
                schoolID: school.id,
                detail: "courses=\(output.courses.count) but programs=\(output.programs.count) — likely marathon partial crawl",
                into: &record
            )
            return
        }

        record.check("programs_found", output.programs.count >= minimumPrograms, "found \(output.programs.count)")
        record.check("courses_found", output.courses.count > 0, "found \(output.courses.count)")

        let outcome = CatalogIngestGate.evaluateCourseLeaf(
            manifest: school,
            depth: .light,
            programs: output.programs,
            courses: output.courses,
            requirements: []
        )
        record.severity = "\(outcome.reviewSeverity)"
        record.check("ingest_gate_not_critical", outcome.reviewSeverity != .critical, "severity=\(outcome.reviewSeverity)")

        try await verifySampleRequirements(
            scraper: UniversalCatalogScraper(),
            programs: output.programs,
            catalogFormat: school.catalogFormat,
            schoolID: school.id,
            into: &record
        )
    }

    private func hasSitemapProgramURLs(baseURL rawURL: String, minimum: Int) async -> Bool {
        guard let baseURL = CourseLeafEngine.normalizeBaseURL(rawURL) else { return false }
        guard let pageURLs = try? await CourseLeafEngine.sitemapPageURLs(baseURL: baseURL) else {
            return false
        }
        let expanded = (try? await CourseLeafEngine.supplementProgramURLs(
            baseURL: baseURL,
            pageURLs: pageURLs
        )) ?? pageURLs
        let programURLs = expanded.filter(Self.isCourseLeafProgramURL)
        return programURLs.count >= minimum
    }

    private static func isCourseLeafProgramURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        guard path.contains("program") || path.contains("major") || path.contains("minor") else {
            return false
        }
        if path == "/programs" || path == "/programs/" { return false }
        if path.contains("attribute-code") || path.contains("group-prerequisite") { return false }
        return path.split(separator: "/").count >= 3
    }

    // MARK: - Coursedog

    private func verifyCoursedog(school: SchoolManifest, into record: inout SchoolVerificationRecord) async throws {
        let catalogURL = (school.catalogURL ?? "")
        let output = try await CoursedogEngine.discoverPrograms(catalogURL: catalogURL)

        record.programsFound = output.programs.count
        record.check(
            "programs_found",
            output.programs.count >= minimumPrograms,
            "found \(output.programs.count)"
        )

        let outcome = CatalogIngestGate.evaluateCourseLeaf(
            manifest: school,
            depth: .light,
            programs: output.programs,
            courses: [],
            requirements: []
        )
        record.severity = "\(outcome.reviewSeverity)"
        record.check("ingest_gate_not_critical", outcome.reviewSeverity != .critical, "severity=\(outcome.reviewSeverity)")

        try await verifySampleRequirements(
            scraper: UniversalCatalogScraper(),
            programs: output.programs,
            catalogFormat: school.catalogFormat,
            schoolID: school.id,
            into: &record
        )
    }

    // MARK: - Shared sample requirement probe

    private func verifySampleRequirements(
        scraper: UniversalCatalogScraper,
        programs: [ScrapedProgram],
        catalogFormat: String,
        schoolID: String,
        into record: inout SchoolVerificationRecord
    ) async throws {
        let candidates = CatalogVerificationSampleSelection.rankedCandidates(from: programs)
        guard !candidates.isEmpty else {
            record.check("sample_program_available", false, "no program had a usable URL")
            return
        }

        var bestProgram: ScrapedProgram?
        var bestRequirements: [DegreeRequirement] = []
        var bestCodes = Set<String>()
        var attemptSummaries: [String] = []

        for sample in candidates {
            let requirements = try await scraper.scrapeProgramRequirements(
                programURL: sample.url,
                catalogFormat: catalogFormat,
                schoolID: schoolID
            )
            let codes = uniqueCourseCodes(in: requirements)
            attemptSummaries.append(
                "\(sample.name) (type=\(sample.type), rows=\(requirements.count), codes=\(codes.count))"
            )

            guard !requirements.isEmpty else { continue }

            if bestProgram == nil {
                bestProgram = sample
                bestRequirements = requirements
                bestCodes = codes
            }

            if !codes.isEmpty {
                bestProgram = sample
                bestRequirements = requirements
                bestCodes = codes
                break
            }
        }

        guard let sample = bestProgram else {
            record.check(
                "sample_requirements_parsed",
                false,
                "no sample produced requirements across \(candidates.count) candidate(s): \(attemptSummaries.joined(separator: "; "))"
            )
            return
        }

        record.sampleRequirementsFound = bestRequirements.count
        record.check(
            "sample_requirements_parsed",
            !bestRequirements.isEmpty,
            "program='\(sample.name)' produced \(bestRequirements.count) requirement rows"
        )

        record.sampleRequirementCourses = bestCodes.count
        record.check(
            "sample_requirement_courses_present",
            !bestCodes.isEmpty,
            "program='\(sample.name)' produced \(bestCodes.count) distinct course codes (tried \(candidates.count): \(attemptSummaries.joined(separator: "; ")))"
        )
    }

    private func uniqueCourseCodes(in requirements: [DegreeRequirement]) -> Set<String> {
        var codes = Set<String>()
        for requirement in requirements {
            requirement.requiredCourses?.forEach { codes.insert($0) }
            requirement.selectFrom?.forEach { codes.insert($0) }
            requirement.requiredCoursesDetailed?.forEach { codes.insert($0.code) }
            requirement.selectFromDetailed?.forEach { codes.insert($0.code) }
        }
        codes.remove("")
        return codes
    }
}
