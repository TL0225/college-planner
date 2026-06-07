// CatalogBackgroundSyncRunner.swift
// Feature: Core
// Purpose: Core module — Hooks.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit
import os
import PDFKit

/// Shared ModernCampus / GitHub catalog sync used from onboarding, Settings, and the menu bar.
///
/// **Isolation contract (Phase 7d):**
/// - Type stays `@MainActor` for ingest commit, local store writes, menu-bar toasts, and UI hooks.
/// - Network + disk: `nonisolated downloadToTemporaryFileWithProgress`, `scrapeModernCampusPhaseBCourses`.
/// - PDF parse: `Task.detached` around `CatalogPDFPipeline.run`; results merged on the main actor.
/// - Do not add in-memory `Data` download helpers here — stream to temp files only.
@MainActor
enum CatalogBackgroundSyncRunner {
    private static let poiLog = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)
    private static let ingestSignatureKeyPrefix = "catalog.ingest.signature.v1."
    private static let forceNextRescrapeKey = "catalog.ingest.forceNext.v1"

    nonisolated static func supportsLiveIngestCoordinator(format rawFormat: String) -> Bool {
        let format = rawFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return format == "acalog" || format == "moderncampus" || format == "courseleaf"
    }

    static func ingestSignatureKey(schoolID: String, format: String, depth: CatalogSyncDepth) -> String {
        "\(ingestSignatureKeyPrefix)\(schoolID).\(format).\(depth == .light ? "light" : "full")"
    }

    static func storedIngestSignature(schoolID: String, format: String, depth: CatalogSyncDepth) -> String? {
        UserDefaults.standard.string(forKey: ingestSignatureKey(schoolID: schoolID, format: format, depth: depth))
    }

    static func setStoredIngestSignature(_ signature: String, schoolID: String, format: String, depth: CatalogSyncDepth) {
        UserDefaults.standard.set(signature, forKey: ingestSignatureKey(schoolID: schoolID, format: format, depth: depth))
    }

    static var shouldForceNextRescrape: Bool {
        UserDefaults.standard.bool(forKey: forceNextRescrapeKey)
    }

    static func setForceNextRescrape(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: forceNextRescrapeKey)
    }

    static func consumeForceNextRescrapeIfNeeded() -> Bool {
        let force = shouldForceNextRescrape
        if force { UserDefaults.standard.set(false, forKey: forceNextRescrapeKey) }
        return force
    }

    private static let courseLeafProgramIndexMigrationKey = "catalog.courseleaf.program-index.v2.migrated"

    /// One-time nudge so existing installs re-index CourseLeaf program lists after parser/provenance fixes.
    static func applyCourseLeafProgramIndexV2MigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: courseLeafProgramIndexMigrationKey) else { return }
        setForceNextRescrape(true)
        UserDefaults.standard.set(true, forKey: courseLeafProgramIndexMigrationKey)
    }

    /// Streams a remote resource to a temp file (Phase 2 P0 — avoids holding full PDF in RAM).
    nonisolated static func downloadToTemporaryFileWithProgress(
        from remoteURL: URL,
        onProgress: @MainActor @escaping (_ completedBytes: Int, _ totalBytes: Int) -> Void,
        onRetry: (@MainActor (_ resumeFromBytes: Int, _ attempt: Int) -> Void)? = nil,
        expectedMimeTypes: Set<String> = []
    ) async throws -> URL {
        func validateResponse(_ response: URLResponse, expectedMimeTypes: Set<String>) throws {
            if response.url?.isFileURL == true { return }
            guard let http = response as? HTTPURLResponse else {
                throw ScraperError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) || http.statusCode == 206 else {
                throw ScraperError.invalidResponse
            }
            guard !expectedMimeTypes.isEmpty else { return }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let matchesExpectedMime = expectedMimeTypes.contains { expected in
                contentType.contains(expected.lowercased())
            }
            guard matchesExpectedMime else { throw ScraperError.invalidResponse }
        }

        func parseTotalLength(from response: URLResponse) -> Int? {
            if let http = response as? HTTPURLResponse,
               let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let slash = cr.lastIndex(of: "/") {
                let totalStr = cr[cr.index(after: slash)...]
                if let total = Int(totalStr) { return total }
            }
            let expected = Int(response.expectedContentLength)
            return expected > 0 ? expected : nil
        }

        let fm = FileManager.default
        let partURL = fm.temporaryDirectory
            .appendingPathComponent("CatalogDownload-\(UUID().uuidString).part")
        if fm.fileExists(atPath: partURL.path) {
            try? fm.removeItem(at: partURL)
        }
        fm.createFile(atPath: partURL.path, contents: nil)

        let maxAttempts = 4
        var attempt = 0
        var totalLengthHint: Int?

        while true {
            attempt += 1
            let offset: Int = {
                guard let attrs = try? fm.attributesOfItem(atPath: partURL.path),
                      let size = attrs[.size] as? NSNumber else { return 0 }
                return size.intValue
            }()

            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 90
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if offset > 0 {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            }

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                try validateResponse(response, expectedMimeTypes: expectedMimeTypes)

                if let hinted = parseTotalLength(from: response) {
                    totalLengthHint = hinted
                }

                let handle = try FileHandle(forWritingTo: partURL)
                if offset > 0 {
                    try handle.seekToEnd()
                }
                defer { try? handle.close() }

                var completedBytes = offset
                var receivedSinceProgress = 0
                var chunk = Data()
                chunk.reserveCapacity(131_072)

                for try await byte in bytes {
                    chunk.append(byte)
                    if chunk.count >= 131_072 {
                        try handle.write(contentsOf: chunk)
                        completedBytes += chunk.count
                        chunk.removeAll(keepingCapacity: true)
                        receivedSinceProgress += 131_072
                        if receivedSinceProgress >= 131_072 {
                            receivedSinceProgress = 0
                            let total = max(totalLengthHint ?? 0, completedBytes)
                            await MainActor.run { onProgress(completedBytes, total) }
                        }
                    }
                }
                if !chunk.isEmpty {
                    try handle.write(contentsOf: chunk)
                    completedBytes += chunk.count
                }

                let total = max(totalLengthHint ?? 0, completedBytes)
                await MainActor.run { onProgress(completedBytes, total) }
                return partURL
            } catch {
                if attempt >= maxAttempts { throw error }

                let nsError = error as NSError
                let urlErrorCode = nsError.domain == NSURLErrorDomain ? nsError.code : nil
                let retryable = urlErrorCode == NSURLErrorNetworkConnectionLost
                    || urlErrorCode == NSURLErrorCannotConnectToHost
                    || urlErrorCode == NSURLErrorTimedOut
                    || urlErrorCode == NSURLErrorCannotFindHost
                    || urlErrorCode == NSURLErrorNotConnectedToInternet

                guard retryable else { throw error }

                let resumeBytes: Int = {
                    guard let attrs = try? fm.attributesOfItem(atPath: partURL.path),
                          let size = attrs[.size] as? NSNumber else { return 0 }
                    return size.intValue
                }()
                let backoffMs = min(1500 * attempt, 6000)
                if let onRetry {
                    await MainActor.run { onRetry(resumeBytes, attempt + 1) }
                }
                try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                await MainActor.run {
                    onProgress(resumeBytes, max(totalLengthHint ?? 0, resumeBytes))
                }
            }
        }
    }

    private static func acalogURLForcingCatoid(_ rawURL: String, catoid: String) -> String {
        guard var components = URLComponents(string: rawURL) else { return rawURL }
        var queryItems = components.queryItems ?? []
        if let idx = queryItems.firstIndex(where: { $0.name.lowercased() == "catoid" }) {
            queryItems[idx] = URLQueryItem(name: "catoid", value: catoid)
        } else {
            queryItems.append(URLQueryItem(name: "catoid", value: catoid))
        }
        components.queryItems = queryItems
        return components.string ?? rawURL
    }

    private nonisolated static func clearModernCampusCachesIfAvailable() {
        // Newer engine versions no longer expose explicit cache-clearing APIs.
    }

    private static var lastCatalogToastBump = Date.distantPast

    static func throttledToastUpdate(
        notifications: AppNotificationCenter,
        id: UUID,
        message: String,
        progress: Double,
        minInterval: TimeInterval = 0.85
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastCatalogToastBump) >= minInterval else { return }
        lastCatalogToastBump = now
        notifications.update(id: id, message: message, progress: progress)
    }

    /// Scrapes Modern Campus course batches off the main actor; persistence hops via `importIncremental`.
    nonisolated private static func scrapeModernCampusPhaseBCourses(
        catalogs: [ModernCampusCatalogDescriptor],
        manifestID: String,
        manifestName: String,
        normalizedCatalogURL: String,
        schoolID: String,
        recordDeepScrapeDone: Bool,
        toastID: UUID,
        importIncremental: @MainActor @escaping (_ profile: SchoolProfile) async throws -> Void
    ) async throws -> (
        coursesByCode: [String: CatalogCourse],
        perCatalogCourseRows: [(catoid: String, title: String, course: CatalogCourse)]
    ) {
        func normalizeCourseCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }

        var coursesByCode: [String: CatalogCourse] = [:]
        var perCatalogCourseRows: [(catoid: String, title: String, course: CatalogCourse)] = []
        let total = max(1, catalogs.count)

        for (index, catalog) in catalogs.enumerated() {
            let frac = 0.05 + (0.85 * Double(index + 1) / Double(total))
            await MainActor.run {
                CatalogMenuBarProgressNotifier.postCountProgress(
                    completed: index + 1,
                    total: total,
                    title: catalog.title,
                    stage: "Courses"
                )
                NotificationCenter.default.post(
                    name: .collegeCatalogBackgroundImportProgress,
                    object: nil,
                    userInfo: [
                        "fraction": frac,
                        "title": "Courses \(index + 1) / \(total) — \(catalog.title)",
                        "finished": false
                    ]
                )
            }

            var streamedCount = 0
            var streamedChunkIndex = 0
            for try await scrapedCoursesChunk in ModernCampusEngine.streamCourseBatches(
                baseURL: normalizedCatalogURL,
                catoid: catalog.catoid,
                batchSize: 250
            ) {
                streamedChunkIndex += 1
                streamedCount += scrapedCoursesChunk.count
                let toastMessage = "Importing \(catalog.title) courses… (\(streamedCount) rows)"
                await MainActor.run {
                    CatalogMenuBarProgressNotifier.postCountProgress(
                        completed: streamedCount,
                        total: max(streamedCount, 1),
                        title: catalog.title,
                        stage: "Courses"
                    )
                    throttledToastUpdate(
                        notifications: AppNotificationCenter.shared,
                        id: toastID,
                        message: toastMessage,
                        progress: frac
                    )
                }

                if !scrapedCoursesChunk.isEmpty {
                    let incrementalProfile = SchoolProfile(
                        schoolID: manifestID,
                        schoolName: manifestName,
                        catalogURL: normalizedCatalogURL,
                        version: "1.0.0-onboarding-stream-\(streamedChunkIndex)",
                        lastUpdated: Date(),
                        courses: scrapedCoursesChunk,
                        degreeRequirements: [],
                        policies: SchoolPolicies(
                            transferCreditLimit: nil,
                            minorTransferLimit: nil,
                            maxCreditsPerSemester: nil,
                            minCreditsForFullTime: nil,
                            gradeForCredit: nil,
                            repeatCoursePolicy: nil
                        )
                    )
                    try await importIncremental(incrementalProfile)
                }

                if !recordDeepScrapeDone {
                    for course in scrapedCoursesChunk {
                        perCatalogCourseRows.append((catoid: catalog.catoid, title: catalog.title, course: course))
                    }
                }
                for course in scrapedCoursesChunk {
                    let key = normalizeCourseCode(course.courseCode)
                    if coursesByCode[key] == nil {
                        coursesByCode[key] = CatalogCourse(
                            id: course.id,
                            courseCode: key,
                            title: course.title,
                            description: course.description,
                            credits: course.credits,
                            department: course.department,
                            prerequisites: course.prerequisites,
                            prerequisiteText: course.prerequisiteText,
                            corequisites: course.corequisites,
                            typicallyOffered: course.typicallyOffered
                        )
                    }
                }
                try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
            }
            clearModernCampusCachesIfAvailable()
        }

        return (coursesByCode, perCatalogCourseRows)
    }

    static func saveChunkedMajors(
        _ rows: [(name: String, degreeLevel: String, degreeType: String?, isMinor: Bool, department: String?, url: String?, resolvedDepartment: String?, resolvedCollege: String?, mappingConfidence: Double?, mappingSource: String?, requirements: [DegreeRequirement]?)],
        for universityName: String,
        schoolID: String,
        collegePersistence: CollegePersistence
    ) throws {
        guard !rows.isEmpty else { return }
        let batchSize = 40
        for start in stride(from: 0, to: rows.count, by: batchSize) {
            try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
            let end = min(start + batchSize, rows.count)
            let batch = Array(rows[start..<end]).map { row in
                (
                    name: row.name,
                    degreeLevel: row.degreeLevel,
                    degreeType: row.degreeType,
                    isMinor: row.isMinor,
                    department: row.department,
                    url: row.url,
                    resolvedDepartment: row.resolvedDepartment,
                    resolvedCollege: row.resolvedCollege,
                    mappingConfidence: row.mappingConfidence,
                    mappingSource: row.mappingSource,
                    requirements: row.requirements,
                    trackVariant: nil as String?,
                    parentProgramKey: nil as String?
                )
            }
            try CatalogProgramWriteBridge.savePrograms(
                batch,
                for: universityName,
            )
            CatalogMenuBarProgressNotifier.postCountProgress(
                completed: end,
                total: rows.count,
                title: universityName,
                stage: "Programs"
            )
        }
    }

    static func saveChunkedMajorsWithCatoid(
        _ rows: [(name: String, degreeLevel: String, degreeType: String?, isMinor: Bool, department: String?, url: String?, resolvedDepartment: String?, resolvedCollege: String?, mappingConfidence: Double?, mappingSource: String?, requirements: [DegreeRequirement]?, sourceCatalogCatoid: String?, trackVariant: String?, parentProgramKey: String?, catalogStableID: UUID?, provenanceJSON: String?)],
        for universityName: String,
        schoolID: String,
        collegePersistence: CollegePersistence
    ) throws {
        guard !rows.isEmpty else { return }
        let batchSize = 40
        for start in stride(from: 0, to: rows.count, by: batchSize) {
            try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
            let end = min(start + batchSize, rows.count)
            let batch = Array(rows[start..<end])
            try CatalogProgramWriteBridge.savePrograms(
                batch,
                for: universityName,
                pruneStalePrograms: false,
            )
            CatalogMenuBarProgressNotifier.postCountProgress(
                completed: end,
                total: rows.count,
                title: universityName,
                stage: "Programs"
            )
        }
        try CatalogProgramWriteBridge.finishChunkedProgramsPrune(
            rows,
            for: universityName
        )
    }

    static func buildMajorRows(
        from programs: [ScrapedProgram],
        extractedRequirements: [DegreeRequirement],
        mappingSource: String,
        degreeLevelForProgram: (ScrapedProgram) -> String,
        urlTransform: (ScrapedProgram) -> String? = { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) }
    ) -> [(name: String, degreeLevel: String, degreeType: String?, isMinor: Bool, department: String?, url: String?, resolvedDepartment: String?, resolvedCollege: String?, mappingConfidence: Double?, mappingSource: String?, requirements: [DegreeRequirement]?, trackVariant: String?, parentProgramKey: String?)] {
        programs.map { program in
            let normalizedType = program.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawDegreeType = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDegreeType = (rawDegreeType ?? "").lowercased()
            let isCredentialLike = normalizedType.contains("certificate")
                || normalizedType.contains("credential")
                || normalizedDegreeType.contains("certificate")
                || normalizedDegreeType.contains("credential")
            let isMinor = normalizedType.contains("minor") && !isCredentialLike
            let degreeType: String? = {
                if let rawDegreeType, !rawDegreeType.isEmpty {
                    if let canonical = DegreeTypeNormalizer.normalize(rawDegreeType) {
                        return canonical.storageToken
                    }
                    return rawDegreeType
                }
                if normalizedType.contains("certificate") { return "Certificate" }
                if normalizedType.contains("credential") { return "Credential" }
                if isMinor { return "Minor" }
                return nil
            }()

            let requirementsForProgram = extractedRequirements.filter {
                $0.major.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(program.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }
            let deptTrimmed = program.department?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dept = (deptTrimmed?.isEmpty ?? true) ? nil : deptTrimmed
            return (
                name: program.name,
                degreeLevel: degreeLevelForProgram(program),
                degreeType: degreeType,
                isMinor: isMinor,
                department: dept,
                url: urlTransform(program),
                resolvedDepartment: dept,
                resolvedCollege: program.college,
                mappingConfidence: nil,
                mappingSource: mappingSource,
                requirements: {
                    if let programReqs = program.requirements, !programReqs.isEmpty { return programReqs }
                    if !requirementsForProgram.isEmpty { return requirementsForProgram }
                    return nil
                }(),
                trackVariant: program.trackVariant,
                parentProgramKey: program.parentProgramURL
            )
        }
    }

    @discardableResult
    static func persistStructuredCatalogIngest(
        collegePersistence: CollegePersistence,
        universityName: String,
        snapshot: CatalogIngestSnapshot,
        commitReason: String,
        signature: String? = nil,
        signatureFormat: String? = nil,
        signatureDepth: CatalogSyncDepth? = nil
    ) -> CatalogReconcileSummary {
        _ = collegePersistence.setActiveUniversity(named: universityName)
        CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: universityName)
        let summary = CatalogIngestReconciler.reconcile(after: snapshot)
        if let uni = collegePersistence.getActiveUniversity() {
            CatalogIngestPipeline.postCatalogDataDidCommit(
                universityID: uni.id,
                reason: commitReason
            )
        }
        if let signature, let signatureFormat, let signatureDepth {
            setStoredIngestSignature(
                signature,
                schoolID: snapshot.schoolID,
                format: signatureFormat,
                depth: signatureDepth
            )
        }
        return summary
    }

    /// `light`: program index only (fast onboarding). `full`: scrape degree requirements for every program (heavy).
    enum CatalogSyncDepth: Sendable {
        case light
        case full
    }

    /// Whether ingest actually ran, or exited early (unchanged PDF, index already present, etc.).
    enum CatalogIngestSyncOutcome: Sendable {
        case completed(scheduledPassB: Bool)
        case skipped(message: String)

        var scheduledPassB: Bool {
            if case .completed(let scheduled) = self { return scheduled }
            return false
        }
    }

    enum VisualPhase {
        case discovering
        case downloading
        case importing
    }

    struct Hooks {
        var onVisualPhase: ((VisualPhase) -> Void)?
        var onProgress: ((Double, String) -> Void)?
        var onCatalogsDiscovered: (([ModernCampusCatalogDescriptor]) -> Void)?
        var onCatalogIndexStarted: ((String, String) -> Void)?
        var onCatalogIndexFinished: ((String, Bool) -> Void)?
    }

    static func matchSchoolManifest(named schoolName: String, in schools: [SchoolManifest]) -> SchoolManifest? {
        let target = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let exact = schools.first(where: { $0.name.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }

        return schools.first(where: {
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.localizedCaseInsensitiveContains(target) || target.localizedCaseInsensitiveContains(name)
        })
    }

    static func resolveSchoolManifest(named schoolName: String, githubService: GitHubDataService) async throws -> SchoolManifest {
        let normalizedTarget = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else {
            throw GitHubError.invalidData
        }

        let cached = githubService.loadResolvedSchoolsList()
        if let found = matchSchoolManifest(named: normalizedTarget, in: cached) {
            return found
        }

        let fetched = try await githubService.refreshResolvedSchoolsList()

        if let found = matchSchoolManifest(named: normalizedTarget, in: fetched) {
            return found
        }

        throw GitHubError.invalidData
    }

    /// Phase A indexes programs (and optionally full requirement pages); Phase B imports courses in a detached task. Returns `true` when Phase B was scheduled.
    static func runModernCampusCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogSyncDepth = .light,
        hooks: Hooks?
    ) async throws -> CatalogIngestSyncOutcome {
        let syncSignpost = OSSignpostID(log: poiLog)
        os_signpost(.begin, log: poiLog, name: "CatalogSync.Run", signpostID: syncSignpost)
        defer { os_signpost(.end, log: poiLog, name: "CatalogSync.Run", signpostID: syncSignpost) }
        CatalogIngestCheckpoint.clearCancel(schoolID: manifest.id)
        try CatalogIngestCheckpoint.throwIfCancelled(schoolID: manifest.id)
        let startedAt = Date()

        let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else {
            throw ScraperError.invalidURL
        }
        CatalogPlatformProbe.enqueueMismatchWarningIfNeeded(manifest: manifest, catalogURL: catalogURL)

        notifications.update(id: toastID, message: "Discovering catalogs…", progress: 0.2)
        hooks?.onVisualPhase?(.discovering)
        hooks?.onProgress?(0.2, "Discovering ModernCampus catalogs...")

        let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        guard let baseURL = URL(string: normalizedCatalogURL) else {
            throw ScraperError.invalidURL
        }

        let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []
        let postedCatalogs = ModernCampusCatalogLabels.filterPostedCatalogs(from: discovered)
        let catalogsToScrape: [ModernCampusCatalogDescriptor]
        if !postedCatalogs.isEmpty {
            catalogsToScrape = postedCatalogs
        } else {
            let catalogID: String
            if let catoidHint, !catoidHint.isEmpty {
                catalogID = catoidHint
            } else {
                catalogID = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
            }
            catalogsToScrape = [ModernCampusCatalogDescriptor(catoid: catalogID, title: "Catalog")]
        }

        hooks?.onCatalogsDiscovered?(catalogsToScrape)

        let useModernCampusIR = CatalogPlatformFlags.modernCampusIREnabled
            && CatalogPlatformFlags.documentIREnabled
        var catalogGraph: CatalogGraph?
        if useModernCampusIR {
            catalogGraph = try await ModernCampusCatalogDiscoverer.buildGraph(
                manifest: manifest,
                baseURL: baseURL,
                catalogs: catalogsToScrape
            )
            DebugLogger.shared.log(
                "[ModernCampusGraph] school=\(manifest.id) nodes=\(catalogGraph?.nodeCount ?? 0) extractable=\(catalogGraph?.extractablePageURLs.count ?? 0) ir=\(useModernCampusIR)",
                category: .scraper,
                level: .info
            )
        }

        let catalogSignatureSource = catalogsToScrape
            .map { "\($0.catoid)|\($0.title)" }
            .sorted()
            .joined(separator: "||")
        let signatureDigest = SHA256.hash(data: Data(catalogSignatureSource.utf8))
        let ingestSignature = signatureDigest.map { String(format: "%02x", $0) }.joined()
        let forceRescrape = consumeForceNextRescrapeIfNeeded()
        if !forceRescrape,
           storedIngestSignature(schoolID: manifest.id, format: "moderncampus", depth: depth) == ingestSignature {
            notifications.update(
                id: toastID,
                message: "Catalog unchanged — skipped incremental sync.",
                progress: 1
            )
            hooks?.onProgress?(1, "Catalog unchanged — skipped.")
            return .skipped(message: "Catalog unchanged — skipped incremental sync.")
        }

        var programsByCatalogAndURL: [String: ScrapedProgram] = [:]
        var irMetadataByProgramURL: [String: ModernCampusCatalogIngestAdapter.ProgramRowMetadata] = [:]
        var dominantLayoutProfileID: String?
        var irCoursesCollected: [CatalogCourse] = []
        let programIndexOnly = (depth == .light)

        for (index, catalog) in catalogsToScrape.enumerated() {
            await Task.yield()
            let catalogSignpost = OSSignpostID(log: poiLog)
            os_signpost(
                .begin,
                log: poiLog,
                name: "CatalogSync.Catalog",
                signpostID: catalogSignpost,
                "catoid=%{public}@ index=%{public}d",
                catalog.catoid,
                index + 1
            )
            let ordinal = index + 1
            let fraction = Double(ordinal) / Double(max(1, catalogsToScrape.count))
            let progress = 0.2 + (0.35 * fraction)
            let msg: String
            let toastDetail: String
            if programIndexOnly {
                msg = "Indexing programs (\(ordinal)/\(catalogsToScrape.count))..."
                toastDetail = "Indexing programs: \(catalog.title.isEmpty ? "catalog" : catalog.title)… (\(ordinal)/\(catalogsToScrape.count))"
            } else {
                msg = String(
                    format: String(
                        localized: "catalog.sync.phase.requirements_fmt",
                        defaultValue: "Fetching degree requirements (%1$d/%2$d)…"
                    ),
                    ordinal,
                    catalogsToScrape.count
                )
                toastDetail = String(
                    format: String(
                        localized: "catalog.sync.phase.requirements_catalog_fmt",
                        defaultValue: "Fetching requirements: %@ (%d/%d)"
                    ),
                    catalog.title.isEmpty ? String(localized: "catalog.sync.catalog_fallback", defaultValue: "catalog") : catalog.title,
                    ordinal,
                    catalogsToScrape.count
                )
            }

            notifications.update(
                id: toastID,
                message: toastDetail,
                progress: progress
            )
            hooks?.onVisualPhase?(.discovering)
            hooks?.onProgress?(progress, msg)

            let catalogTitle = ModernCampusCatalogLabels.postedDisplayTitle(from: catalog.title)
            hooks?.onCatalogIndexStarted?(catalog.catoid, catalogTitle)

            let programScraper = UniversalCatalogScraper()
            let catalogIDInt = Int(catalog.catoid) ?? 0
            let catalogVersion = CatalogVersion.resolve(
                school: manifest,
                segment: .modernCampus(catalog)
            )
            do {
                let scrapedPrograms: [ScrapedProgram]
                var irScrapeResult: ModernCampusCatalogIngestAdapter.ScrapeResult?
                if useModernCampusIR, let catalogGraph {
                    let irResult = try await ModernCampusCatalogIngestAdapter.scrapeProgramsViaIR(
                        graph: catalogGraph,
                        manifest: manifest,
                        catalog: catalog,
                        programsIndexOnly: programIndexOnly
                    )
                    irScrapeResult = irResult
                    irCoursesCollected.append(contentsOf: irResult.courses)
                    for (key, meta) in irResult.metadataByProgramURL {
                        irMetadataByProgramURL[key] = meta
                    }
                    if let profile = irResult.dominantLayoutProfileID {
                        dominantLayoutProfileID = profile
                    }
                    if ModernCampusCatalogIngestAdapter.shouldFallbackToUniversalScraper(
                        irProgramCount: irResult.programs.count,
                        host: baseURL.host
                    ) {
                        scrapedPrograms = try await programScraper.scrapeAllPrograms(
                            baseURL: baseURL,
                            catalogID: catalogIDInt,
                            programsIndexOnly: programIndexOnly,
                            schoolID: manifest.id,
                            catalogVersionID: catalogVersion.id
                        )
                    } else {
                        scrapedPrograms = irResult.programs
                    }
                } else {
                    scrapedPrograms = try await programScraper.scrapeAllPrograms(
                        baseURL: baseURL,
                        catalogID: catalogIDInt,
                        programsIndexOnly: programIndexOnly,
                        schoolID: manifest.id,
                        catalogVersionID: catalogVersion.id
                    )
                }
                await ModernCampusCatalogIngestAdapter.persistDocumentIRIfNeeded(
                    manifest: manifest,
                    catalog: catalog,
                    graph: catalogGraph,
                    scraper: programScraper,
                    irScrapeResult: irScrapeResult,
                    layoutProfileID: dominantLayoutProfileID
                )
                await Task.yield()
                for program in scrapedPrograms {
                    let normalizedURL = program.url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    let dedupStem = normalizedURL.isEmpty
                        ? program.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        : normalizedURL
                    let dedupKey = "\(catalog.catoid)|\(dedupStem)"
                    programsByCatalogAndURL[dedupKey] = program
                }
            } catch {
                hooks?.onCatalogIndexFinished?(catalog.catoid, false)
                throw error
            }
            hooks?.onCatalogIndexFinished?(catalog.catoid, true)
            os_signpost(.end, log: poiLog, name: "CatalogSync.Catalog", signpostID: catalogSignpost)
        }

        let programs = Array(programsByCatalogAndURL.values)

        var extractedRequirements: [DegreeRequirement] = []
        for program in programs {
            extractedRequirements.append(contentsOf: program.requirements ?? [])
        }

        var ingestGateOutcome: CatalogIngestGate.Outcome?
        if CatalogPlatformFlags.ingestGateEnabled {
            let gate = CatalogIngestGate.evaluateModernCampus(
                manifest: manifest,
                depth: depth,
                programs: programs,
                courses: irCoursesCollected,
                requirements: extractedRequirements,
                layoutProfileID: dominantLayoutProfileID,
                expectCourses: false
            )
            ingestGateOutcome = gate
            if gate.shouldAbortIngest {
                throw ScraperError.parsingFailed
            }
            if !gate.allowsRequirements {
                extractedRequirements = []
                for (key, program) in programsByCatalogAndURL {
                    programsByCatalogAndURL[key] = ScrapedProgram(
                        name: program.name,
                        type: program.type,
                        url: program.url,
                        group: program.group,
                        department: program.department,
                        college: program.college,
                        degreeType: program.degreeType,
                        requirements: nil,
                        trackVariant: program.trackVariant,
                        parentProgramURL: program.parentProgramURL
                    )
                }
            }
        }

        hooks?.onVisualPhase?(.importing)
        notifications.update(id: toastID, message: "Saving program list…", progress: 0.58)
        hooks?.onProgress?(0.58, "Saving \(programs.count) programs...")

        let emptyProfile = SchoolProfile(
            schoolID: manifest.id,
            schoolName: manifest.name,
            catalogURL: normalizedCatalogURL,
            version: "1.0.0-onboarding-programs",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )

        try await collegePersistence.importSchoolCatalog(
            emptyProfile,
            policy: .preserveExistingCourses
        )

        var departmentToGroup: [String: String] = [:]
        for (dedupKey, program) in programsByCatalogAndURL {
            let department = (program.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !department.isEmpty else { continue }

            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let catalogLabel = catalogMeta.map {
                ModernCampusCatalogLabels.postedDisplayTitle(from: $0.title)
            } ?? "Catalog \(catoidFromKey)"

            let preferredGroup = (program.college ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let group = preferredGroup.isEmpty ? catalogLabel : preferredGroup

            if departmentToGroup[department] == nil {
                departmentToGroup[department] = group
            }
        }

        if !departmentToGroup.isEmpty {
            let rows = departmentToGroup.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { dept in
                (name: dept, code: nil as String?, school: departmentToGroup[dept])
            }
            try CatalogProgramWriteBridge.saveDepartments(
                rows,
                for: manifest.name
            )
        }

        func inferDegreeLevel(programType: String, degreeType: String?) -> String {
            if programType.lowercased().contains("minor") {
                return "Undergraduate"
            }

            let token = (degreeType ?? "").uppercased()
            if token.contains("PHD") { return "PhD" }

            let undergrad = ["BA", "BS", "BFA", "BM", "BARCH"]
            if undergrad.contains(where: { token.contains($0) }) { return "Undergraduate" }

            let graduate = ["MA", "MS", "MBA", "MENG", "MFA", "JD", "MD", "DDS", "DMD", "PHARMD"]
            if graduate.contains(where: { token.contains($0) }) { return "Graduate" }

            return "Undergraduate"
        }

        func saveRow(
            program: ScrapedProgram,
            catalogDegreeLevel: String,
            sourceCatalogCatoid: String,
            dedupStem: String
        ) -> (
            name: String,
            degreeLevel: String,
            degreeType: String?,
            isMinor: Bool,
            department: String?,
            url: String?,
            resolvedDepartment: String?,
            resolvedCollege: String?,
            mappingConfidence: Double?,
            mappingSource: String?,
            provenanceJSON: String?,
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?,
            trackVariant: String?,
            parentProgramKey: String?
        ) {
            let trimmedCatoid = sourceCatalogCatoid.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawProgramURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let transformedURL: String? = {
                guard !rawProgramURL.isEmpty else { return nil }
                guard !trimmedCatoid.isEmpty else { return rawProgramURL }
                return acalogURLForcingCatoid(rawProgramURL, catoid: trimmedCatoid)
            }()
            let baseRow = CatalogBackgroundSyncRunner.buildMajorRows(
                from: [program],
                extractedRequirements: [],
                mappingSource: "onboarding.moderncampus",
                degreeLevelForProgram: { _ in catalogDegreeLevel },
                urlTransform: { _ in transformedURL }
            ).first!

            let meta = irMetadataByProgramURL[dedupStem]
                ?? irMetadataByProgramURL[rawProgramURL]
            let mappingSource: String
            let mappingConfidence: Double?
            let provenanceJSON: String?
            if let meta {
                mappingSource = "onboarding.moderncampus.ir|\(meta.layoutProfileID)"
                mappingConfidence = meta.layoutConfidence
                provenanceJSON = meta.provenance.jsonString()
            } else {
                mappingSource = baseRow.mappingSource ?? "onboarding.moderncampus"
                mappingConfidence = baseRow.mappingConfidence
                provenanceJSON = nil
            }

            return (
                name: baseRow.name,
                degreeLevel: baseRow.degreeLevel,
                degreeType: baseRow.degreeType,
                isMinor: baseRow.isMinor,
                department: baseRow.department,
                url: baseRow.url,
                resolvedDepartment: baseRow.resolvedDepartment,
                resolvedCollege: baseRow.resolvedCollege,
                mappingConfidence: mappingConfidence,
                mappingSource: mappingSource,
                provenanceJSON: provenanceJSON,
                requirements: baseRow.requirements,
                sourceCatalogCatoid: sourceCatalogCatoid,
                trackVariant: nil as String?,
                parentProgramKey: nil as String?
            )
        }

        var rows: [(
            name: String,
            degreeLevel: String,
            degreeType: String?,
            isMinor: Bool,
            department: String?,
            url: String?,
            resolvedDepartment: String?,
            resolvedCollege: String?,
            mappingConfidence: Double?,
            mappingSource: String?,
            provenanceJSON: String?,
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?,
            trackVariant: String?,
            parentProgramKey: String?
        )] = []

        for (dedupKey, program) in programsByCatalogAndURL.sorted(by: { $0.key < $1.key }) {
            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let bucket = catalogMeta.map { ModernCampusCatalogLabels.postedDisplayTitle(from: $0.title) }
                ?? "Catalog \(catoidFromKey)"
            let dedupStem = dedupKey.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init)
                ?? program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(
                saveRow(
                    program: program,
                    catalogDegreeLevel: bucket,
                    sourceCatalogCatoid: catoidFromKey,
                    dedupStem: dedupStem
                )
            )
        }

        if rows.isEmpty {
            if let downloaded = try? await githubService.downloadSchoolProfile(schoolID: manifest.id) {
                var seen = Set<String>()
                rows = downloaded.degreeRequirements.compactMap { req in
                    let major = req.major.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !major.isEmpty else { return nil }

                    let degreeType = req.degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isMinor = degreeType.lowercased().contains("minor") || major.lowercased().contains("minor")
                    let key = "\(major.lowercased())|\(degreeType.lowercased())|\(isMinor)"
                    guard seen.insert(key).inserted else { return nil }

                    return (
                        name: major,
                        degreeLevel: inferDegreeLevel(programType: isMinor ? "Minor" : "Major", degreeType: degreeType),
                        degreeType: degreeType.isEmpty ? (isMinor ? "Minor" : nil) : degreeType,
                        isMinor: isMinor,
                        department: nil as String?,
                        url: "",
                        resolvedDepartment: nil as String?,
                        resolvedCollege: nil as String?,
                        mappingConfidence: nil as Double?,
                        mappingSource: "onboarding.profile-fallback",
                        provenanceJSON: nil as String?,
                        requirements: nil as [DegreeRequirement]?,
                        sourceCatalogCatoid: nil as String?,
                        trackVariant: nil as String?,
                        parentProgramKey: nil as String?
                    )
                }
            }
        }

        if !rows.isEmpty {
            let provenanceRows = rows.filter { $0.provenanceJSON != nil }.count
            if provenanceRows > 0 {
                DebugLogger.shared.log(
                    "[ModernCampusIR] school=\(manifest.id) programsWithProvenance=\(provenanceRows)/\(rows.count) layout=\(dominantLayoutProfileID ?? "unknown")",
                    category: .scraper,
                    level: .info
                )
            }
            try saveChunkedMajorsWithCatoid(
                rows.map { row in
                    (
                        name: row.name,
                        degreeLevel: row.degreeLevel,
                        degreeType: row.degreeType,
                        isMinor: row.isMinor,
                        department: row.department,
                        url: row.url,
                        resolvedDepartment: row.resolvedDepartment,
                        resolvedCollege: row.resolvedCollege,
                        mappingConfidence: row.mappingConfidence,
                        mappingSource: row.mappingSource,
                        requirements: row.requirements,
                        sourceCatalogCatoid: row.sourceCatalogCatoid,
                        trackVariant: row.trackVariant,
                        parentProgramKey: row.parentProgramKey,
                        catalogStableID: nil,
                        provenanceJSON: row.provenanceJSON
                    )
                },
                for: manifest.name,
                schoolID: manifest.id,
                collegePersistence: collegePersistence
            )
        }
        CatalogIngestCheckpoint.save(stage: .passA, schoolID: manifest.id, signature: ingestSignature)

        let catoidSummary = catalogsToScrape.map(\.catoid).joined(separator: ",")
        let programsWithRequirements = rows.filter { row in
            guard let reqs = row.requirements else { return false }
            return !reqs.isEmpty
        }.count
        DebugLogger.shared.log(
            "📊 Catalog sync Phase A — catoids=[\(catoidSummary)] programs=\(programs.count) savedRows=\(rows.count) nonemptyRequirements=\(programsWithRequirements) depth=\(depth == .full ? "full" : "light")"
        )

        _ = collegePersistence.setActiveUniversity(named: manifest.name)

        clearModernCampusCachesIfAvailable()

        if depth == .full {
            notifications.update(
                id: toastID,
                message: String(
                    localized: "catalog.sync.phase.course_import_toast",
                    defaultValue: "Program list ready — importing full course catalog in the background…"
                ),
                progress: 0.72
            )
            hooks?.onProgress?(
                0.72,
                String(
                    localized: "catalog.sync.phase.course_import_hooks",
                    defaultValue: "Importing course catalog in the background…"
                )
            )
        } else {
            notifications.update(
                id: toastID,
                message: String(
                    localized: "catalog.sync.phase.skeleton_done_toast",
                    defaultValue: "Program index saved."
                ),
                progress: 0.95
            )
            hooks?.onProgress?(0.95, "Program index saved.")
            hooks?.onVisualPhase?(.importing)
            let requirementCount = rows.reduce(0) { partial, row in
                partial + (row.requirements?.count ?? 0)
            }
            _ = persistStructuredCatalogIngest(
                collegePersistence: collegePersistence,
                universityName: manifest.name,
                snapshot: CatalogIngestSnapshot(
                    schoolID: manifest.id,
                    schoolName: manifest.name,
                    scope: .programsOnly,
                    format: "moderncampus",
                    importedAt: Date(),
                    courseCount: 0,
                    programCount: rows.count,
                    requirementCount: requirementCount,
                    policyCount: 0
                ),
                commitReason: "catalog moderncampus programs committed",
                signature: ingestSignature,
                signatureFormat: "moderncampus",
                signatureDepth: depth
            )
            if let gate = ingestGateOutcome {
                CatalogIngestGate.recordSuccessfulBaseline(gate)
                CatalogIngestObservability.record(
                    gate.metrics.toObservabilitySample(
                        succeeded: true,
                        durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
                        pageCount: max(catalogsToScrape.count, 1)
                    )
                )
            }
            return .completed(scheduledPassB: false)
        }

        let dataManager = collegePersistence
        let notify = notifications
        let catalogsCopy = catalogsToScrape
        let manifestCopy = manifest
        let normalizedURLCopy = normalizedCatalogURL
        let recordDeepScrapeDone = true
        let irCoursesCopy = irCoursesCollected
        let useModernCampusIRCopy = useModernCampusIR
        let dominantLayoutCopy = dominantLayoutProfileID

        Task { @MainActor in
            UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
            NotificationCenter.default.post(
                name: .collegeCatalogBackgroundImportProgress,
                object: nil,
                userInfo: [
                    "fraction": 0.05,
                    "title": "Importing \(manifestCopy.name) courses",
                    "finished": false
                ]
            )

            defer {
                UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
                clearModernCampusCachesIfAvailable()
                NotificationCenter.default.post(
                    name: .collegeCatalogBackgroundImportProgress,
                    object: nil,
                    userInfo: ["finished": true]
                )
            }

            do {
                let scrapeResult = try await Self.scrapeModernCampusPhaseBCourses(
                    catalogs: catalogsCopy,
                    manifestID: manifestCopy.id,
                    manifestName: manifestCopy.name,
                    normalizedCatalogURL: normalizedURLCopy,
                    schoolID: manifestCopy.id,
                    recordDeepScrapeDone: recordDeepScrapeDone,
                    toastID: toastID,
                    importIncremental: { profile in
                        try await dataManager.importSchoolCatalog(
                            profile,
                            policy: .preserveExistingCourses
                        )
                    }
                )
                var perCatalogCourseRows = scrapeResult.perCatalogCourseRows
                var courses = Array(scrapeResult.coursesByCode.values)
                if useModernCampusIRCopy, !irCoursesCopy.isEmpty {
                    let beforeCount = courses.count
                    courses = ModernCampusCatalogIngestAdapter.mergeCourses(
                        primary: courses,
                        irFallback: irCoursesCopy
                    )
                    if courses.count > beforeCount {
                        DebugLogger.shared.log(
                            "[ModernCampusIR] school=\(manifestCopy.id) merged IR course fallback +\(courses.count - beforeCount) stubs",
                            category: .scraper,
                            level: .info
                        )
                    }
                }

                if courses.isEmpty {
                    notify.post(
                        kind: .error,
                        title: String(
                            localized: "catalog.sync.no_courses_title",
                            defaultValue: "No courses imported"
                        ),
                        message: String(
                            localized: "catalog.sync.no_courses_body",
                            defaultValue: "The catalog site did not return any course rows. Check your network, try again, or report if the school's catalog layout changed."
                        ),
                        isDismissible: true,
                        autoDismissAfter: 10
                    )
                }

                if !perCatalogCourseRows.isEmpty {
                    do {
                        _ = try CatalogScrapeAuditCSVSupport.writeAuditFile(manifest: manifestCopy, rows: perCatalogCourseRows)
                    } catch {
                        notify.post(
                            kind: .error,
                            title: "Scrape Export Failed",
                            message: error.localizedDescription,
                            isDismissible: true,
                            autoDismissAfter: 8
                        )
                    }
                }
                perCatalogCourseRows.removeAll(keepingCapacity: false)

                let profile = SchoolProfile(
                    schoolID: manifestCopy.id,
                    schoolName: manifestCopy.name,
                    catalogURL: normalizedURLCopy,
                    version: "1.0.0-onboarding-scraped",
                    lastUpdated: Date(),
                    courses: courses,
                    degreeRequirements: [],
                    policies: SchoolPolicies(
                        transferCreditLimit: nil,
                        minorTransferLimit: nil,
                        maxCreditsPerSemester: nil,
                        minCreditsForFullTime: nil,
                        gradeForCredit: nil,
                        repeatCoursePolicy: nil
                    )
                )

                DebugLogger.shared.log(
                    "📊 Catalog sync Phase B — mergedUniqueCourses=\(courses.count) catalogsScanned=\(catalogsCopy.count) school=\(manifestCopy.name)"
                )

                if !courses.isEmpty {
                    try await dataManager.importSchoolCatalog(profile)
                    _ = dataManager.setActiveUniversity(named: manifestCopy.name)
                    CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: manifestCopy.name)

                    if useModernCampusIRCopy, CatalogPlatformFlags.documentIREnabled {
                        let catalogVersion = CatalogVersion.resolve(school: manifestCopy, segment: .manifestOnly)
                        try await CourseLeafCatalogIngestAdapter.persistCourseMetadata(
                            courses: courses,
                            manifest: manifestCopy,
                            schoolID: manifestCopy.id,
                            catalogVersionID: catalogVersion.id,
                            layoutProfileID: dominantLayoutCopy ?? "moderncampus-ir",
                            ingestRunID: UUID(),
                            existingIdentities: CatalogEntityIdentityStore.load(
                                schoolID: manifestCopy.id,
                                catalogVersionID: catalogVersion.id
                            )
                        )
                    }

                    if CatalogPlatformFlags.ingestGateEnabled {
                        let courseGate = CatalogIngestGate.evaluateModernCampus(
                            manifest: manifestCopy,
                            depth: .full,
                            programs: [],
                            courses: courses,
                            requirements: [],
                            layoutProfileID: dominantLayoutCopy,
                            expectCourses: true
                        )
                        if !courseGate.shouldAbortIngest {
                            CatalogIngestGate.recordSuccessfulBaseline(courseGate)
                            CatalogIngestObservability.record(
                                courseGate.metrics.toObservabilitySample(
                                    succeeded: true,
                                    durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
                                    pageCount: max(catalogsCopy.count, 1)
                                )
                            )
                        }
                    }
                    _ = CatalogIngestReconciler.reconcile(
                        after: CatalogIngestSnapshot(
                            schoolID: manifestCopy.id,
                            schoolName: manifestCopy.name,
                            scope: .fullSchool,
                            format: "moderncampus",
                            importedAt: Date(),
                            courseCount: courses.count,
                            programCount: rows.count,
                            requirementCount: 0,
                            policyCount: 0
                        )
                    )
                    if let uni = dataManager.getActiveUniversity() {
                        CatalogIngestPipeline.postCatalogDataDidCommit(
                            universityID: uni.id,
                            reason: "catalog phaseB committed"
                        )
                    }
                    clearModernCampusCachesIfAvailable()

                    _ = try? dataManager.exportCatalogBundle(for: manifestCopy.name)
                    _ = try? CatalogStorePortableBridge.exportSignedCatalogStore(for: manifestCopy.name)

                    if recordDeepScrapeDone {
                        UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey)
                    }
                    CatalogIngestCheckpoint.save(stage: .passB, schoolID: manifestCopy.id, signature: ingestSignature)

                    setStoredIngestSignature(
                        ingestSignature,
                        schoolID: manifestCopy.id,
                        format: "moderncampus",
                        depth: .full
                    )

                    notify.post(
                        kind: .success,
                        title: "Catalog Import Complete",
                        message: "\(manifestCopy.name): \(courses.count) courses saved.",
                        isDismissible: true,
                        autoDismissAfter: 4
                    )
                }
            } catch {
                notify.post(
                    kind: .error,
                    title: "Background Catalog Import Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 8
                )
            }
        }

        return .completed(scheduledPassB: true)
    }

    /// Start or restart catalog sync for the user’s school (Settings / menu bar / Overview). Safe to call when not onboarding.
    static func runUserInitiatedCatalogSync(
        schoolName: String,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        depth: CatalogSyncDepth = .full
    ) async {
        let githubService = GitHubDataService()
        let trimmed = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            notifications.post(
                kind: .error,
                title: String(localized: "catalog.sync.no_school_title", defaultValue: "No school selected"),
                message: String(localized: "catalog.sync.no_school_body", defaultValue: "Set your college or university in Profile first."),
                isDismissible: true,
                autoDismissAfter: 6
            )
            CatalogMenuBarProgressNotifier.postFinished()
            return
        }

        if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
            notifications.post(
                kind: .info,
                title: String(localized: "catalog.sync.already_running_title", defaultValue: "Catalog import running"),
                message: String(localized: "catalog.sync.already_running_body", defaultValue: "Wait for the current import to finish, then you can start another."),
                isDismissible: true,
                autoDismissAfter: 5
            )
            return
        }

        CatalogMenuBarProgressNotifier.postInProgress(
            fraction: 0,
            title: String(localized: "catalog.sync.menubar_starting", defaultValue: "Starting catalog sync…"),
            indeterminate: true
        )

        let toastID = notifications.post(
            kind: .progress,
            title: String(localized: "catalog.sync.toast_title", defaultValue: "Catalog Sync"),
            message: String(format: String(localized: "catalog.sync.resolving_fmt", defaultValue: "Resolving %@…"), trimmed),
            progress: 0.05,
            isDismissible: true
        )

        do {
            notifications.update(id: toastID, message: String(localized: "catalog.sync.loading_manifest", defaultValue: "Loading school manifest…"), progress: 0.15)
            CatalogMenuBarProgressNotifier.postInProgress(
                fraction: 0.12,
                title: String(localized: "catalog.sync.menubar_manifest", defaultValue: "Loading school manifest…"),
                indeterminate: false
            )

            let manifest = try await resolveSchoolManifest(named: trimmed, githubService: githubService)
            let canonicalSchoolName = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = collegePersistence.setActiveUniversity(named: canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName)

            let format = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let shouldUseCatalogIngestCoordinator = supportsLiveIngestCoordinator(format: format)

            var scheduledBackgroundCourseImport = false
            var skippedMessage: String?
            if shouldUseCatalogIngestCoordinator {
                let menuBarHooks = Hooks(
                    onVisualPhase: { _ in },
                    onProgress: { fraction, title in
                        CatalogMenuBarProgressNotifier.postInProgress(
                            fraction: fraction,
                            title: title,
                            indeterminate: false
                        )
                    },
                    onCatalogsDiscovered: { _ in }
                )
                let outcome = try await CatalogIngestCoordinator.runCatalogSync(
                    manifest: manifest,
                    toastID: toastID,
                    collegePersistence: collegePersistence,
                    notifications: notifications,
                    githubService: githubService,
                    depth: depth,
                    hooks: menuBarHooks
                )
                switch outcome {
                case .completed(let scheduled):
                    scheduledBackgroundCourseImport = scheduled
                case .skipped(let message):
                    skippedMessage = message
                }
            } else {
                notifications.update(id: toastID, message: String(localized: "catalog.sync.discovering_profile", defaultValue: "Discovering catalog profile…"), progress: 0.2)
                CatalogMenuBarProgressNotifier.postInProgress(
                    fraction: 0.25,
                    title: String(localized: "catalog.sync.menubar_downloading_profile", defaultValue: "Downloading school profile…"),
                    indeterminate: false
                )
                let profile = try await githubService.downloadSchoolProfile(schoolID: manifest.id)

                notifications.update(id: toastID, message: String(localized: "catalog.sync.importing", defaultValue: "Importing catalog to local database…"), progress: 0.75)
                CatalogMenuBarProgressNotifier.postInProgress(
                    fraction: 0.75,
                    title: String(localized: "catalog.sync.menubar_importing_db", defaultValue: "Importing catalog to database…"),
                    indeterminate: false
                )
                try await collegePersistence.importSchoolCatalog(profile)
                _ = persistStructuredCatalogIngest(
                    collegePersistence: collegePersistence,
                    universityName: canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName,
                    snapshot: CatalogIngestSnapshot(
                        schoolID: manifest.id,
                        schoolName: canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName,
                        scope: .fullSchool,
                        format: "profile",
                        importedAt: Date(),
                        courseCount: profile.courses.count,
                        programCount: 0,
                        requirementCount: profile.degreeRequirements.count,
                        policyCount: 0
                    ),
                    commitReason: "catalog profile committed"
                )
                if depth == .full {
                    UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey)
                }
            }

            if !scheduledBackgroundCourseImport {
                UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
                CatalogMenuBarProgressNotifier.postFinished()
            }

            let readyLabel = canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName
            if let skippedMessage {
                notifications.complete(
                    id: toastID,
                    kind: .info,
                    title: String(localized: "catalog.sync.skipped_title", defaultValue: "Catalog sync skipped"),
                    message: skippedMessage,
                    autoDismissAfter: 6
                )
            } else if scheduledBackgroundCourseImport {
                notifications.complete(
                    id: toastID,
                    kind: .success,
                    title: String(localized: "catalog.sync.partial_title", defaultValue: "Catalog Sync Started"),
                    message: String(
                        format: String(
                            localized: "catalog.sync.partial_body_fmt",
                            defaultValue: "%@ program index is ready. Full course import is continuing in the background."
                        ),
                        readyLabel
                    ),
                    autoDismissAfter: 5
                )
            } else {
                notifications.complete(
                    id: toastID,
                    kind: .success,
                    title: String(localized: "catalog.sync.ready_title", defaultValue: "Catalog Ready"),
                    message: String(format: String(localized: "catalog.sync.ready_body_fmt", defaultValue: "%@ is synced and ready."), readyLabel),
                    autoDismissAfter: 4
                )
            }
        } catch {
            notifications.dismiss(id: toastID)
            notifications.post(
                kind: .error,
                title: String(localized: "catalog.sync.failed_title", defaultValue: "Catalog Sync Failed"),
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 6
            )
            UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
            CatalogMenuBarProgressNotifier.postFinished()
        }
    }
}

// MARK: - Unified catalog ingest router (v1: acalog/moderncampus/courseleaf + pdf stub)
// CourseLeaf program requirements are parsed from each program page's `index.xml` only (never public HTML).

@MainActor
enum CatalogIngestCoordinator {
    static func runCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth = .full,
        hooks: CatalogBackgroundSyncRunner.Hooks? = nil
    ) async throws -> CatalogBackgroundSyncRunner.CatalogIngestSyncOutcome {
        let format = manifest.catalogFormat
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch format {
        case "acalog", "moderncampus":
            return try await CatalogBackgroundSyncRunner.runModernCampusCatalogSync(
                manifest: manifest,
                toastID: toastID,
                collegePersistence: collegePersistence,
                notifications: notifications,
                githubService: githubService,
                depth: depth,
                hooks: hooks
            )

        case "courseleaf":
            return try await CourseLeafCatalogIngestAdapter.runCourseLeafCatalogSync(
                manifest: manifest,
                toastID: toastID,
                collegePersistence: collegePersistence,
                notifications: notifications,
                githubService: githubService,
                depth: depth,
                hooks: hooks
            )

        default:
            // Router handles known live ingestion formats. Others use profile fallback callers.
            throw ScraperError.parsingFailed
        }
    }
}

@MainActor
enum CourseLeafCatalogIngestAdapter {
    /// Minimum stored rows before we treat a CourseLeaf skeleton index as complete (NYU ≈ 200+ majors).
    private static let minimumMajorsForCompleteIndex = 40
    private static let minimumDepartmentsForCompleteIndex = 2

    static func onboardingProgramIndexLooksComplete(
        presence: (courses: Int, departments: Int, majors: Int, minors: Int)
    ) -> Bool {
        guard presence.majors + presence.minors > 0 else { return false }
        guard presence.majors >= minimumMajorsForCompleteIndex else { return false }
        guard presence.departments >= minimumDepartmentsForCompleteIndex else { return false }
        return true
    }

    static func runCourseLeafCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        hooks: CatalogBackgroundSyncRunner.Hooks?
    ) async throws -> CatalogBackgroundSyncRunner.CatalogIngestSyncOutcome {
        let schoolID = manifest.id
        let startedAt = Date()
        let ingestRunID = UUID()
        let catalogVersion = CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
        let catalogURLString = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURLString.isEmpty else { throw ScraperError.invalidURL }
        CatalogPlatformProbe.enqueueMismatchWarningIfNeeded(manifest: manifest, catalogURL: catalogURLString)

        hooks?.onVisualPhase?(.discovering)
        hooks?.onProgress?(0.1, "Discovering CourseLeaf catalogs…")
        notifications.update(id: toastID, message: "Discovering CourseLeaf catalogs…", progress: 0.1)

        guard let normalizedBase = CourseLeafEngine.normalizeBaseURL(catalogURLString) else {
            throw ScraperError.invalidURL
        }
        await CourseLeafSitemapCache.clear()
        let sitemapPageURLs = try await CourseLeafSitemapCache.pageURLs(baseURL: normalizedBase)

        let onboardingCatalogs = CourseLeafCatalogSegmentDiscoverer.onboardingCatalogs(
            pageURLs: sitemapPageURLs,
            schoolID: schoolID
        )
        let catalogsToScrape = CourseLeafCatalogSegmentDiscoverer.catalogDescriptors(from: onboardingCatalogs)
        hooks?.onCatalogsDiscovered?(catalogsToScrape)

        let graph = CourseLeafCatalogDiscoverer.buildGraph(
            manifest: manifest,
            baseURL: normalizedBase,
            pageURLs: sitemapPageURLs
        )
        if CatalogPlatformFlags.documentIREnabled {
            let extractable = graph.extractablePageURLs
            DebugLogger.shared.log(
                "[CourseLeafGraph] school=\(schoolID) nodes=\(graph.nodeCount) extractable=\(extractable.count)",
                category: .scraper,
                level: .info
            )
            _ = extractable
        }

        CatalogBackgroundSyncRunner.applyCourseLeafProgramIndexV2MigrationIfNeeded()

        let catalogSignatureSource = "courseleaf-program-index.v2||" + catalogsToScrape
            .map { "\($0.catoid)|\($0.title)" }
            .sorted()
            .joined(separator: "||")
        let signatureDigest = SHA256.hash(data: Data(catalogSignatureSource.utf8))
        let ingestSignature = signatureDigest.map { String(format: "%02x", $0) }.joined()

        let forceRescrape = CatalogBackgroundSyncRunner.consumeForceNextRescrapeIfNeeded()
        if !forceRescrape,
           CatalogBackgroundSyncRunner.storedIngestSignature(schoolID: schoolID, format: "courseleaf", depth: depth) == ingestSignature {
            let presence = await collegePersistence.catalogPresence(universityName: manifest.name)
            if CourseLeafCatalogIngestAdapter.onboardingProgramIndexLooksComplete(presence: presence) {
                let message = "CourseLeaf catalog unchanged — skipped incremental sync."
                hooks?.onProgress?(1.0, message)
                notifications.update(id: toastID, message: message, progress: 1.0)
                return .skipped(message: message)
            }
        }

        hooks?.onProgress?(0.15, "Indexing CourseLeaf bulletin…")
        notifications.update(id: toastID, message: "Indexing CourseLeaf bulletin…", progress: 0.15)

        let parseRequirementsDuringCrawl = (depth == .full)
        let crawlPageURLs: [URL] = CatalogPlatformFlags.documentIREnabled
            ? graph.extractablePageURLs.compactMap { URL(string: $0) }
            : sitemapPageURLs
        let versionByURL: [String: String]? = CatalogPlatformFlags.documentIREnabled
            ? Dictionary(
                uniqueKeysWithValues: graph.nodes.map { ($0.url, $0.catalogVersionID) }
            )
            : nil
        let output = try await CourseLeafEngine.crawlCatalog(
            baseURL: catalogURLString,
            schoolID: schoolID,
            parseRequirements: parseRequirementsDuringCrawl,
            preferredPageURLs: crawlPageURLs,
            catalogVersionIDByPageURL: versionByURL
        )

        var programsBySegmentAndURL: [String: ScrapedProgram] = [:]
        let programIndexOnly = (depth == .light)
        let catalogsToIndex = onboardingCatalogs.isEmpty
            ? [CourseLeafCatalogSegmentDiscoverer.OnboardingCatalog(
                id: "\(schoolID)_catalog",
                displayName: manifest.name,
                pathPrefixes: ["/"]
            )]
            : onboardingCatalogs

        for (index, catalog) in catalogsToIndex.enumerated() {
            await Task.yield()
            let ordinal = index + 1
            let fraction = Double(ordinal) / Double(max(1, catalogsToIndex.count))
            let progress = 0.2 + (0.35 * fraction)
            let msg = "Indexing programs (\(ordinal)/\(catalogsToIndex.count))..."
            let toastDetail = "Indexing programs: \(catalog.displayName)… (\(ordinal)/\(catalogsToIndex.count))"

            notifications.update(id: toastID, message: toastDetail, progress: progress)
            hooks?.onVisualPhase?(.discovering)
            hooks?.onProgress?(progress, msg)
            hooks?.onCatalogIndexStarted?(catalog.id, catalog.displayName)

            let catalogPrograms = output.programs.filter { program in
                CourseLeafCatalogSegmentDiscoverer.programMatchesCatalog(url: program.url, catalog: catalog)
            }

            for program in catalogPrograms {
                let normalizedURL = program.url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let dedupStem = normalizedURL.isEmpty
                    ? program.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    : normalizedURL
                let dedupKey = "\(catalog.id)|\(dedupStem)"
                programsBySegmentAndURL[dedupKey] = program
            }

            hooks?.onCatalogIndexFinished?(catalog.id, true)
        }

        let indexedProgramKeys = Set(
            programsBySegmentAndURL.values.map { program in
                let normalizedURL = program.url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !normalizedURL.isEmpty { return normalizedURL }
                return program.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
        )
        for program in output.programs {
            let normalizedURL = program.url.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let dedupStem = normalizedURL.isEmpty
                ? program.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                : normalizedURL
            if indexedProgramKeys.contains(dedupStem) { continue }

            let catalog = CourseLeafCatalogSegmentDiscoverer.bestMatchingOnboardingCatalog(
                forProgramURL: program.url,
                in: catalogsToIndex
            ) ?? catalogsToIndex.first
            guard let catalog else { continue }

            let dedupKey = "\(catalog.id)|\(dedupStem)"
            programsBySegmentAndURL[dedupKey] = program
        }

        var programs = Array(programsBySegmentAndURL.values)
        var extractedRequirements: [DegreeRequirement] = []

        if depth == .full, !programs.isEmpty {
            hooks?.onProgress?(0.58, "Extracting CourseLeaf requirements…")
            notifications.update(id: toastID, message: "Extracting CourseLeaf requirements…", progress: 0.58)
            var enrichedByURL: [String: ScrapedProgram] = [:]
            for program in programs {
                let trimmedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedURL.isEmpty else { continue }
                var requirements = program.requirements ?? []
                if requirements.isEmpty {
                    requirements = (try? await CourseLeafRequirementsParser.scrapeRequirements(
                        programURL: trimmedURL,
                        schoolID: schoolID,
                        degreeType: program.degreeType
                    )) ?? []
                }
                extractedRequirements.append(contentsOf: requirements)
                enrichedByURL[trimmedURL] = ScrapedProgram(
                    name: program.name,
                    type: program.type,
                    url: program.url,
                    group: program.group,
                    department: program.department,
                    college: program.college,
                    degreeType: program.degreeType,
                    requirements: requirements.isEmpty ? nil : requirements,
                    trackVariant: program.trackVariant,
                    parentProgramURL: program.parentProgramURL
                )
            }
            for (key, program) in programsBySegmentAndURL {
                let trimmedURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if let enriched = enrichedByURL[trimmedURL] {
                    programsBySegmentAndURL[key] = enriched
                }
            }
            programs = Array(programsBySegmentAndURL.values)
        }

        let telemetry = CatalogIngestTelemetrySession(
            schoolID: schoolID,
            source: "courseleaf",
            startedAt: startedAt,
            endedAt: Date(),
            pagesDiscovered: 0,
            pagesClassified: 0,
            coursesExtracted: output.courses.count,
            programsExtracted: programs.count,
            anomalies: []
        )

        let layoutProfileID = output.dominantLayoutProfileID
            ?? CatalogLayoutProfileRegistry.preferredProfileID(forSchoolID: schoolID)?.rawValue
            ?? "legacy-courseleaf"
        let layoutConfidence = output.layoutConfidence ?? 0.75

        var ingestGateOutcome: CatalogIngestGate.Outcome?
        if CatalogPlatformFlags.ingestGateEnabled {
            let gate = CatalogIngestGate.evaluateCourseLeaf(
                manifest: manifest,
                depth: depth,
                programs: programs,
                courses: output.courses,
                requirements: extractedRequirements,
                layoutProfileID: layoutProfileID,
                averageEntityConfidence: layoutConfidence,
                averageOwnershipConfidence: layoutConfidence
            )
            ingestGateOutcome = gate
            if gate.shouldAbortIngest {
                throw ScraperError.parsingFailed
            }
            if !gate.allowsRequirements {
                extractedRequirements = []
                for (key, program) in programsBySegmentAndURL {
                    programsBySegmentAndURL[key] = ScrapedProgram(
                        name: program.name,
                        type: program.type,
                        url: program.url,
                        group: program.group,
                        department: program.department,
                        college: program.college,
                        degreeType: program.degreeType,
                        requirements: nil,
                        trackVariant: program.trackVariant,
                        parentProgramURL: program.parentProgramURL
                    )
                }
                programs = Array(programsBySegmentAndURL.values)
            }
        }

        hooks?.onVisualPhase?(.importing)
        notifications.update(id: toastID, message: "Saving program list…", progress: 0.62)
        hooks?.onProgress?(0.62, "Saving \(programs.count) programs...")

        let emptyProfile = SchoolProfile(
            schoolID: schoolID,
            schoolName: manifest.name,
            catalogURL: catalogURLString,
            version: programIndexOnly ? "1.0.0-courseleaf-onboarding-programs" : "1.0.0-courseleaf",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        try await collegePersistence.importSchoolCatalog(
            emptyProfile,
            policy: .preserveExistingCourses
        )

        var departmentToGroup: [String: String] = [:]
        for (dedupKey, program) in programsBySegmentAndURL {
            let department = (program.department ?? program.college ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !department.isEmpty else { continue }

            let catalogID = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToIndex.first { $0.id == catalogID }
            let catalogLabel = catalogMeta?.displayName ?? "Catalog"

            // DepartmentEntity.school holds the catalog level (Undergraduate / Graduate), not the college slug.
            if departmentToGroup[department] == nil {
                departmentToGroup[department] = catalogLabel
            }
        }

        if !departmentToGroup.isEmpty {
            let rows = departmentToGroup.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { dept in
                (name: dept, code: nil as String?, school: departmentToGroup[dept])
            }
            try CatalogProgramWriteBridge.saveDepartments(
                rows,
                for: manifest.name
            )
        }

        var entityIdentities: [CatalogEntityIdentity] = []
        if let repo = AppDataStore.shared.catalogRepository,
           let university = try? repo.fetchUniversity(named: manifest.name) {
            entityIdentities = (try? CatalogIngestPersistenceHelpers.loadMergedIdentities(
                repo: repo,
                universityID: university.id,
                schoolID: schoolID,
                catalogVersionID: catalogVersion.id
            )) ?? CatalogEntityIdentityStore.load(schoolID: schoolID, catalogVersionID: catalogVersion.id)
        } else {
            entityIdentities = CatalogEntityIdentityStore.load(schoolID: schoolID, catalogVersionID: catalogVersion.id)
        }
        let identitiesBeforeIngest = entityIdentities

        var rows: [(
            name: String,
            degreeLevel: String,
            degreeType: String?,
            isMinor: Bool,
            department: String?,
            url: String?,
            resolvedDepartment: String?,
            resolvedCollege: String?,
            mappingConfidence: Double?,
            mappingSource: String?,
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?,
            trackVariant: String?,
            parentProgramKey: String?,
            catalogStableID: UUID?,
            provenanceJSON: String?
        )] = []

        for (dedupKey, program) in programsBySegmentAndURL.sorted(by: { $0.key < $1.key }) {
            let catalogID = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToIndex.first { $0.id == catalogID }
            let catalogLabel = catalogMeta?.displayName ?? "Catalog"
            let baseRow = CatalogBackgroundSyncRunner.buildMajorRows(
                from: [program],
                extractedRequirements: extractedRequirements,
                mappingSource: "onboarding.courseleaf",
                degreeLevelForProgram: { _ in catalogLabel }
            ).first!

            let (stableID, identity) = CatalogIngestPersistenceHelpers.resolveProgramStableID(
                program: program,
                catalogVersionID: catalogVersion.id,
                existing: entityIdentities
            )
            entityIdentities.append(identity)
            let provenance = CatalogProvenance(
                sourceURL: program.url,
                layoutProfileID: layoutProfileID,
                documentNodeID: stableID,
                catalogVersionID: catalogVersion.id,
                ingestRunID: ingestRunID
            )

            rows.append((
                name: baseRow.name,
                degreeLevel: baseRow.degreeLevel,
                degreeType: baseRow.degreeType,
                isMinor: baseRow.isMinor,
                department: baseRow.department,
                url: baseRow.url,
                resolvedDepartment: baseRow.resolvedDepartment,
                resolvedCollege: baseRow.resolvedCollege,
                mappingConfidence: layoutConfidence,
                mappingSource: baseRow.mappingSource,
                requirements: baseRow.requirements,
                sourceCatalogCatoid: catalogID,
                trackVariant: baseRow.trackVariant,
                parentProgramKey: baseRow.parentProgramKey,
                catalogStableID: stableID,
                provenanceJSON: CatalogIngestPersistenceHelpers.encodeProvenanceJSON(provenance)
            ))
        }

        CatalogIngestPersistenceHelpers.persistIdentities(
            entityIdentities,
            schoolID: schoolID,
            catalogVersionID: catalogVersion.id
        )
        let structuralDiff = CatalogStructuralDiffEngine.diff(
            schoolID: schoolID,
            catalogVersionID: catalogVersion.id,
            previous: identitiesBeforeIngest,
            current: entityIdentities
        )
        if structuralDiff.hasChanges {
            CatalogStructuralDiffStore.save(structuralDiff)
        }

        if rows.isEmpty, let fallback = try? await githubService.downloadSchoolProfile(schoolID: schoolID) {
            try await collegePersistence.importSchoolCatalog(
                fallback,
                policy: .preserveExistingCourses
            )
        }

        if !rows.isEmpty {
            try CatalogBackgroundSyncRunner.saveChunkedMajorsWithCatoid(
                rows,
                for: manifest.name,
                schoolID: schoolID,
                collegePersistence: collegePersistence
            )
        }

        _ = collegePersistence.setActiveUniversity(named: manifest.name)

        if depth == .full, !output.courses.isEmpty {
            let profile = SchoolProfile(
                schoolID: schoolID,
                schoolName: manifest.name,
                catalogURL: catalogURLString,
                version: "1.0.0-courseleaf",
                lastUpdated: Date(),
                courses: output.courses,
                // Requirements are persisted per programURL in saveMajors; bulk import used
                // major="Unknown" keys and overwrote/shadowed breakdown rows.
                degreeRequirements: [],
                policies: SchoolPolicies(
                    transferCreditLimit: nil,
                    minorTransferLimit: nil,
                    maxCreditsPerSemester: nil,
                    minCreditsForFullTime: nil,
                    gradeForCredit: nil,
                    repeatCoursePolicy: nil
                )
            )
            try await collegePersistence.importSchoolCatalog(
                profile,
                policy: .preserveExistingCourses
            )
            try await CourseLeafCatalogIngestAdapter.persistCourseMetadata(
                courses: output.courses,
                manifest: manifest,
                schoolID: schoolID,
                catalogVersionID: catalogVersion.id,
                layoutProfileID: layoutProfileID,
                ingestRunID: ingestRunID,
                existingIdentities: entityIdentities
            )
        }

        let requirementCount = rows.reduce(0) { partial, row in
            partial + (row.requirements?.count ?? 0)
        }

        _ = CatalogBackgroundSyncRunner.persistStructuredCatalogIngest(
            collegePersistence: collegePersistence,
            universityName: manifest.name,
            snapshot: CatalogIngestSnapshot(
                schoolID: schoolID,
                schoolName: manifest.name,
                scope: depth == .light ? .programsOnly : .fullSchool,
                format: "courseleaf",
                importedAt: Date(),
                courseCount: depth == .full ? output.courses.count : 0,
                programCount: rows.count,
                requirementCount: requirementCount,
                policyCount: 0
            ),
            commitReason: depth == .light ? "catalog courseleaf programs committed" : "catalog courseleaf committed",
            signature: depth == .light ? ingestSignature : output.sourceSignature,
            signatureFormat: "courseleaf",
            signatureDepth: depth
        )

        if let gate = ingestGateOutcome {
            CatalogIngestGate.recordSuccessfulBaseline(gate)
            CatalogIngestObservability.record(
                gate.metrics.toObservabilitySample(
                    succeeded: true,
                    durationMs: max(1, Int(telemetry.endedAt.timeIntervalSince(telemetry.startedAt) * 1000)),
                    pageCount: max(catalogsToIndex.count, 1)
                )
            )
        } else {
            CatalogIngestObservability.record(
                CatalogIngestMetricSample(
                    schoolID: telemetry.schoolID,
                    source: telemetry.source,
                    succeeded: true,
                    durationMs: max(1, Int(telemetry.endedAt.timeIntervalSince(telemetry.startedAt) * 1000)),
                    pageCount: max(catalogsToIndex.count, 1),
                    ocrPagesUsed: 0,
                    averageProgramConfidence: nil,
                    timestamp: telemetry.endedAt,
                    programsFound: programs.count,
                    coursesFound: output.courses.count,
                    requirementsFound: extractedRequirements.count
                )
            )
        }

        let doneMessage = programIndexOnly ? "Program index saved." : "CourseLeaf sync complete."
        notifications.update(id: toastID, message: doneMessage, progress: 1.0)
        hooks?.onProgress?(1.0, doneMessage)
        return .completed(scheduledPassB: false)
    }

    static func persistCourseMetadata(
        courses: [CatalogCourse],
        manifest: SchoolManifest,
        schoolID: String,
        catalogVersionID: String,
        layoutProfileID: String,
        ingestRunID: UUID,
        existingIdentities: [CatalogEntityIdentity]
    ) async throws {
        guard let repo = AppDataStore.shared.catalogRepository,
              let university = try repo.fetchUniversity(named: manifest.name) else {
            return
        }

        var identities = existingIdentities
        var codeToStableID: [String: UUID] = [:]
        var inputs: [CatalogRepository.CourseUpsertInput] = []

        let enrichedCourses = courses.map {
            CatalogExternalReferenceBuilder.enriching(
                $0,
                engine: manifest.catalogFormat,
                schoolID: schoolID
            )
        }

        for course in enrichedCourses {
            let code = CatalogImportTransforms.normalizeCourseCode(course.courseCode)
            guard !code.isEmpty else { continue }
            let (stableID, identity) = CatalogIngestPersistenceHelpers.resolveCourseStableID(
                courseCode: code,
                catalogVersionID: catalogVersionID,
                existing: identities
            )
            identities.append(identity)
            codeToStableID[code] = stableID

            let provenance = CatalogProvenance(
                sourceURL: course.previewDetailURL ?? "",
                layoutProfileID: layoutProfileID,
                documentNodeID: course.id,
                catalogVersionID: catalogVersionID,
                ingestRunID: ingestRunID
            )
            var prerequisiteJSON: String?
            if let rule = course.prerequisites,
               let data = try? JSONEncoder().encode(rule) {
                prerequisiteJSON = String(data: data, encoding: .utf8)
            }

            inputs.append(
                CatalogRepository.CourseUpsertInput(
                    courseCode: code,
                    title: course.title,
                    credits: Int16(max(0, course.credits)),
                    descriptionText: course.description,
                    department: course.department,
                    isArchived: false,
                    catalogStableID: stableID,
                    provenanceJSON: CatalogIngestPersistenceHelpers.encodeProvenanceJSON(provenance),
                    prerequisiteRulesJSON: prerequisiteJSON
                )
            )
        }

        if !inputs.isEmpty {
            try repo.upsertCourses(universityID: university.id, inputs: inputs)
            ModelMergeCoalescer.flushNow()
        }

        CatalogIngestPersistenceHelpers.persistIdentities(
            identities,
            schoolID: schoolID,
            catalogVersionID: catalogVersionID
        )

        let relationships = CatalogPrerequisiteRelationshipBuilder.relationships(
            courses: enrichedCourses,
            catalogVersionID: catalogVersionID,
            codeToStableID: codeToStableID,
            ingestRunID: ingestRunID,
            layoutProfileID: layoutProfileID
        )
        if !relationships.isEmpty {
            CatalogRelationshipStore.save(
                relationships,
                schoolID: schoolID,
                catalogVersionID: catalogVersionID
            )
        }
    }
}

@MainActor
enum PDFCatalogIngestAdapter {
    static func runPDFCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        collegePersistence: CollegePersistence,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogBackgroundSyncRunner.CatalogSyncDepth,
        hooks: CatalogBackgroundSyncRunner.Hooks?
    ) async throws -> CatalogBackgroundSyncRunner.CatalogIngestSyncOutcome {
        let schoolID = manifest.id
        let cachedPDFURL = CatalogArchiveStore.cachedPDFURL(schoolID: schoolID)
        let hasCachedPDF = FileManager.default.fileExists(atPath: cachedPDFURL.path)

        // Fast-path for repeat skeleton syncs: if programs already exist and we have a cached PDF,
        // avoid re-downloading the same bulletin just to confirm readiness.
        let forceRescrape = CatalogBackgroundSyncRunner.consumeForceNextRescrapeIfNeeded()
        if depth == .light, !forceRescrape {
            let caps = await collegePersistence.catalogCapabilities(universityName: manifest.name)
            if caps.programsReady,
               hasCachedPDF,
               CatalogBackgroundSyncRunner.storedIngestSignature(schoolID: schoolID, format: "pdf", depth: depth) != nil {
                _ = collegePersistence.setActiveUniversity(named: manifest.name)
                let skipMessage = "Program index already available — no re-parse."
                hooks?.onProgress?(1, skipMessage)
                notifications.update(
                    id: toastID,
                    message: skipMessage,
                    progress: 1
                )
                CatalogMenuBarProgressNotifier.postSucceeded(title: skipMessage)
                return .skipped(message: skipMessage)
            }
        }

        hooks?.onVisualPhase?(.downloading)
        hooks?.onProgress?(0.2, "Downloading PDF bulletin…")
        notifications.update(
            id: toastID,
            message: "Downloading PDF bulletin…",
            progress: 0.2
        )

        let catalogURLString = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURLString.isEmpty, let remoteURL = URL(string: catalogURLString) else {
            throw ScraperError.invalidURL
        }

        try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
        CatalogIngestCheckpoint.clearCancel(schoolID: schoolID)

        hooks?.onProgress?(0.28, "Downloading PDF bulletin…")
        CatalogMenuBarProgressNotifier.postCountProgress(
            completed: 0,
            total: 1,
            title: manifest.name,
            stage: "Download"
        )
        let localPDFURL: URL
        if depth == .light, hasCachedPDF {
            hooks?.onProgress?(0.28, "Using cached PDF bulletin…")
            notifications.update(
                id: toastID,
                message: "Using cached PDF bulletin…",
                progress: 0.28
            )
            localPDFURL = cachedPDFURL
        } else {
            let downloadedPart = try await CatalogBackgroundSyncRunner.downloadToTemporaryFileWithProgress(
                from: remoteURL,
                onProgress: { completedBytes, totalBytes in
                    CatalogMenuBarProgressNotifier.postCountProgress(
                        completed: completedBytes,
                        total: totalBytes,
                        title: manifest.name,
                        stage: "Download"
                    )
                    let mb: (Int) -> String = { value in
                        let valueMB = Double(value) / 1_048_576.0
                        return String(format: "%.1f MB", valueMB)
                    }
                    hooks?.onProgress?(0.28, "Downloading \(mb(completedBytes)) / \(mb(totalBytes))")
                },
                onRetry: { resumeFromBytes, attempt in
                    let valueMB = Double(resumeFromBytes) / 1_048_576.0
                    let resumeText = String(format: "Reconnecting… resuming at %.1f MB (attempt %d)", valueMB, attempt)
                    hooks?.onProgress?(0.28, resumeText)
                    notifications.update(id: toastID, message: resumeText, progress: 0.28)
                },
                expectedMimeTypes: ["application/pdf", "application/octet-stream"]
            )
            localPDFURL = try CatalogArchiveStore.writeCachedPDF(from: downloadedPart, schoolID: schoolID)
            try? FileManager.default.removeItem(at: downloadedPart)
        }
        CatalogMenuBarProgressNotifier.postCountProgress(
            completed: 1,
            total: 1,
            title: manifest.name,
            stage: "Download"
        )
        let totalPDFPages = max(0, PDFDocument(url: localPDFURL)?.pageCount ?? 0)
        CatalogIngestCheckpoint.save(stage: .passA, schoolID: schoolID, signature: nil)
        let pdfSignature = try CatalogArchiveStore.sha256Hex(of: localPDFURL)
        if !forceRescrape,
           CatalogBackgroundSyncRunner.storedIngestSignature(schoolID: schoolID, format: "pdf", depth: depth) == pdfSignature {
            let skipMessage = "PDF unchanged — no re-parse (same file as last skeleton sync)."
            notifications.update(
                id: toastID,
                message: skipMessage,
                progress: 1
            )
            hooks?.onProgress?(1, skipMessage)
            CatalogMenuBarProgressNotifier.postSucceeded(title: skipMessage)
            return .skipped(message: skipMessage)
        }

        let parseStartMessage: String = {
            if totalPDFPages > 0 {
                return "Parsing pages 0 / \(totalPDFPages)…"
            }
            return "Parsing pages from local PDF…"
        }()
        hooks?.onProgress?(0.45, parseStartMessage)
        hooks?.onVisualPhase?(.importing)
        notifications.update(
            id: toastID,
            message: parseStartMessage,
            progress: 0.45
        )
        if totalPDFPages > 0 {
            CatalogMenuBarProgressNotifier.postCountProgress(
                completed: 0,
                total: totalPDFPages,
                title: manifest.name,
                stage: "Pages"
            )
        }

        let schoolName = manifest.name
        let catalogVersion = CatalogPDFIngestPersistence.catalogVersion(for: manifest)
        let ingestRunID = UUID()
        let extractionResult: CatalogPDFIngestOutput = try await Task.detached(priority: .utility) { () async throws -> CatalogPDFIngestOutput in
            try await CatalogPDFPipeline.run(
                pdfURL: localPDFURL,
                options: CatalogPDFPipeline.Options(
                    schoolID: manifest.id,
                    catalogVersionID: catalogVersion.id,
                    includeCourses: depth == .full,
                    includePolicies: depth == .light,
                    ocrFallback: depth == .full
                ),
                onPageProgress: { completed, total in
                    Task { @MainActor in
                        CatalogMenuBarProgressNotifier.postCountProgress(
                            completed: completed,
                            total: total,
                            title: schoolName,
                            stage: "Pages"
                        )
                    }
                }
            )
        }.value

        guard !extractionResult.programs.isEmpty else {
            throw CatalogPDFError.noProgramsExtracted
        }

        DebugLogger.shared.log(
            "[PDFIngest] \(manifest.name): extracted \(extractionResult.programs.count) programs, " +
            "blocks accepted \(extractionResult.classificationDiagnostics.programAccepted)/" +
            "\(extractionResult.classificationDiagnostics.programCandidates), " +
            "parser=2.0.0-pdf-blocks"
        )

        if let encodedHealth = try? JSONEncoder().encode(extractionResult.healthReport as PDFHealthReport),
           let json = String(data: encodedHealth, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "catalog.pdf.health.\(manifest.id)")
        }

        let extractedRequirements = extractionResult.requirements
        let pdfLayoutProfileID = CatalogPDFIngestPersistence.layoutProfileID(
            for: manifest,
            documentIR: extractionResult.documentIR
        )
        var pdfIngestGateOutcome: CatalogIngestGate.Outcome?
        if CatalogPlatformFlags.ingestGateEnabled {
            let gate = CatalogIngestGate.evaluatePDF(
                manifest: manifest,
                depth: depth,
                programs: extractionResult.programs,
                courses: extractionResult.courses,
                requirements: extractedRequirements,
                policies: extractionResult.policyRows.count,
                layoutProfileID: pdfLayoutProfileID,
                averageProgramConfidence: extractionResult.classificationDiagnostics.averageAcceptedProgramConfidence
            )
            pdfIngestGateOutcome = gate
            if gate.shouldAbortIngest {
                throw ScraperError.parsingFailed
            }
        }

        let policies = SchoolPolicies(
            transferCreditLimit: nil,
            minorTransferLimit: nil,
            maxCreditsPerSemester: nil,
            minCreditsForFullTime: nil,
            gradeForCredit: nil,
            repeatCoursePolicy: nil
        )

        func makeProfile(courses: [CatalogCourse], degreeRequirements: [DegreeRequirement], versionSuffix: String) -> SchoolProfile {
            SchoolProfile(
                schoolID: manifest.id,
                schoolName: manifest.name,
                catalogURL: catalogURLString,
                version: "1.0.0-pdf-\(versionSuffix)",
                lastUpdated: Date(),
                courses: courses,
                degreeRequirements: degreeRequirements,
                policies: policies
            )
        }

        switch depth {
        case .light:
            hooks?.onProgress?(0.65, "Importing programs into app database…")
            notifications.update(
                id: toastID,
                message: "Importing programs into app database…",
                progress: 0.65
            )

            let profile = makeProfile(courses: [], degreeRequirements: extractedRequirements, versionSuffix: "programs")
            try await collegePersistence.importSchoolCatalog(
                profile,
                policy: .preserveExistingCourses
            )
            _ = collegePersistence.setActiveUniversity(named: manifest.name)
            CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: manifest.name)

            if !extractionResult.programs.isEmpty {
                if CatalogPlatformFlags.documentIREnabled {
                    try await CatalogPDFIngestPersistence.persistDocumentIRTrack(
                        extractionResult: extractionResult,
                        manifest: manifest,
                        programs: extractionResult.programs,
                        requirements: extractedRequirements,
                        ingestRunID: ingestRunID,
                        collegePersistence: collegePersistence
                    )
                } else {
                    let majorsToSave = legacyPDFMajorRows(
                        programs: extractionResult.programs,
                        requirements: extractedRequirements
                    )
                    try CatalogBackgroundSyncRunner.saveChunkedMajors(
                        majorsToSave,
                        for: manifest.name,
                        schoolID: manifest.id,
                        collegePersistence: collegePersistence
                    )
                }
            }
            guard !extractionResult.programs.isEmpty else {
                // Fallback for bulletins where PDF program extraction is sparse:
                // use the GitHub profile payload so onboarding can still proceed.
                if let fallbackProfile = try? await githubService.downloadSchoolProfile(schoolID: manifest.id) {
                    try await collegePersistence.importSchoolCatalog(
                        fallbackProfile,
                        policy: .preserveExistingCourses
                    )
                    _ = collegePersistence.setActiveUniversity(named: manifest.name)
                    CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: manifest.name)

                    _ = CatalogIngestReconciler.reconcile(
                        after: CatalogIngestSnapshot(
                            schoolID: manifest.id,
                            schoolName: manifest.name,
                            scope: .programsOnly,
                            format: "pdf",
                            importedAt: Date(),
                            courseCount: fallbackProfile.courses.count,
                            programCount: fallbackProfile.degreeRequirements.map(\.major).count,
                            requirementCount: fallbackProfile.degreeRequirements.count,
                            policyCount: 0
                        )
                    )
                    if let uni = collegePersistence.getActiveUniversity() {
                        CatalogIngestPipeline.postCatalogDataDidCommit(
                            universityID: uni.id,
                            reason: "catalog pdf fallback profile committed"
                        )
                    }
                    CatalogBackgroundSyncRunner.setStoredIngestSignature(pdfSignature, schoolID: manifest.id, format: "pdf", depth: depth)
                    hooks?.onProgress?(0.95, "Imported fallback profile data (PDF program extraction empty).")
                    return .completed(scheduledPassB: false)
                }
                throw ScraperError.parsingFailed
            }
            CatalogCanonicalIRStore.save(
                CatalogCanonicalIR(
                    schoolID: manifest.id,
                    generatedAt: Date(),
                    programs: extractionResult.programs.map {
                        .init(
                            name: $0.name,
                            type: $0.type,
                            department: $0.department ?? "",
                            degreeType: $0.degreeType,
                            provenance: .init(
                                documentURL: manifest.catalogURL ?? "",
                                parserVersion: "2.0.0-pdf-blocks",
                                parserCapabilityVersion: CatalogParserCapability.version,
                                pageStart: nil,
                                pageEnd: nil,
                                confidence: extractionResult.classificationDiagnostics.averageAcceptedProgramConfidence
                            )
                        )
                    },
                    courses: []
                )
            )
            _ = collegePersistence.setActiveUniversity(named: manifest.name)

            await persistPDFIngestDiagnostics(
                manifest: manifest,
                pdfSignature: pdfSignature,
                pageCount: extractionResult.healthReport.pageCount,
                programs: extractionResult.programs.count,
                courses: 0,
                requirements: extractedRequirements.count,
                policies: extractionResult.policyRows.count,
                healthReport: extractionResult.healthReport,
                blockClassification: extractionResult.classificationDiagnostics,
                ocrPagesUsed: extractionResult.ocrPagesUsed,
                documentIR: extractionResult.documentIR,
                collegePersistence: collegePersistence
            )

            if !extractionResult.policyRows.isEmpty {
                let policyRows = extractionResult.policyRows.map { row in
                    (
                        sourceURL: catalogURLString.isEmpty ? row.sourceURL : catalogURLString,
                        navTitle: row.navTitle,
                        sectionHeading: row.sectionHeading ?? "",
                        bodyText: row.bodyText,
                        catalogScope: row.catalogScope,
                        contentHash: row.contentHash,
                        binding: row.binding ?? ""
                    )
                }
                try collegePersistence.replaceCatalogPolicyDocuments(
                    forUniversityName: manifest.name,
                    catoid: manifest.id,
                    rows: policyRows
                )
            }

            _ = CatalogIngestReconciler.reconcile(
                after: CatalogIngestSnapshot(
                    schoolID: manifest.id,
                    schoolName: manifest.name,
                    scope: .programsOnly,
                    format: "pdf",
                    importedAt: Date(),
                    courseCount: 0,
                    programCount: extractionResult.programs.count,
                    requirementCount: extractedRequirements.count,
                    policyCount: extractionResult.policyRows.count
                )
            )

            hooks?.onProgress?(0.9, "PDF program + policies ingest complete.")
            if totalPDFPages > 0 {
                CatalogMenuBarProgressNotifier.postCountProgress(
                    completed: totalPDFPages,
                    total: totalPDFPages,
                    title: manifest.name,
                    stage: "Pages"
                )
            }
            if let uni = collegePersistence.getActiveUniversity() {
                CatalogIngestPipeline.postCatalogDataDidCommit(
                    universityID: uni.id,
                    reason: "catalog pdf programs committed"
                )
            }

            if let gate = pdfIngestGateOutcome {
                CatalogIngestGate.recordSuccessfulBaseline(gate)
            }
            CatalogBackgroundSyncRunner.setStoredIngestSignature(pdfSignature, schoolID: manifest.id, format: "pdf", depth: depth)
            return .completed(scheduledPassB: false)

        case .full:
            guard !extractionResult.courses.isEmpty else {
                throw ScraperError.parsingFailed
            }

            hooks?.onProgress?(0.75, "Importing courses into app database…")
            notifications.update(
                id: toastID,
                message: "Importing courses into app database…",
                progress: 0.75
            )

            let profile = makeProfile(courses: extractionResult.courses, degreeRequirements: extractedRequirements, versionSuffix: "courses-programs")
            try await collegePersistence.importSchoolCatalog(profile)
            _ = collegePersistence.setActiveUniversity(named: manifest.name)
            CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: manifest.name)

            if !extractionResult.programs.isEmpty {
                if CatalogPlatformFlags.documentIREnabled {
                    try await CatalogPDFIngestPersistence.persistDocumentIRTrack(
                        extractionResult: extractionResult,
                        manifest: manifest,
                        programs: extractionResult.programs,
                        requirements: extractedRequirements,
                        ingestRunID: ingestRunID,
                        collegePersistence: collegePersistence
                    )
                } else {
                    let majorsToSave = legacyPDFMajorRows(
                        programs: extractionResult.programs,
                        requirements: extractedRequirements
                    )
                    try CatalogBackgroundSyncRunner.saveChunkedMajors(
                        majorsToSave,
                        for: manifest.name,
                        schoolID: manifest.id,
                        collegePersistence: collegePersistence
                    )
                }
            }

            try await CatalogPDFIngestPersistence.persistCourseMetadataIfNeeded(
                courses: extractionResult.courses,
                manifest: manifest,
                documentIR: extractionResult.documentIR,
                ingestRunID: ingestRunID
            )
            CatalogCanonicalIRStore.save(
                CatalogCanonicalIR(
                    schoolID: manifest.id,
                    generatedAt: Date(),
                    programs: extractionResult.programs.map {
                        .init(
                            name: $0.name,
                            type: $0.type,
                            department: $0.department ?? "",
                            degreeType: $0.degreeType,
                            provenance: .init(
                                documentURL: manifest.catalogURL ?? "",
                                parserVersion: "2.0.0-pdf-blocks",
                                parserCapabilityVersion: CatalogParserCapability.version,
                                pageStart: nil,
                                pageEnd: nil,
                                confidence: extractionResult.classificationDiagnostics.averageAcceptedProgramConfidence
                            )
                        )
                    },
                    courses: extractionResult.courses.map {
                        .init(
                            courseCode: $0.courseCode,
                            title: $0.title,
                            credits: Double($0.credits),
                            department: $0.department ?? "",
                            provenance: .init(
                                documentURL: manifest.catalogURL ?? "",
                                parserVersion: "2.0.0-pdf-blocks",
                                parserCapabilityVersion: CatalogParserCapability.version,
                                pageStart: nil,
                                pageEnd: nil,
                                confidence: nil
                            )
                        )
                    }
                )
            )

            await persistPDFIngestDiagnostics(
                manifest: manifest,
                pdfSignature: pdfSignature,
                pageCount: extractionResult.healthReport.pageCount,
                programs: extractionResult.programs.count,
                courses: extractionResult.courses.count,
                requirements: extractedRequirements.count,
                policies: extractionResult.policyRows.count,
                healthReport: extractionResult.healthReport,
                blockClassification: extractionResult.classificationDiagnostics,
                ocrPagesUsed: extractionResult.ocrPagesUsed,
                documentIR: extractionResult.documentIR,
                collegePersistence: collegePersistence
            )
            _ = CatalogIngestReconciler.reconcile(
                after: CatalogIngestSnapshot(
                    schoolID: manifest.id,
                    schoolName: manifest.name,
                    scope: .fullSchool,
                    format: "pdf",
                    importedAt: Date(),
                    courseCount: extractionResult.courses.count,
                    programCount: extractionResult.programs.count,
                    requirementCount: extractedRequirements.count,
                    policyCount: extractionResult.policyRows.count
                )
            )
            CatalogIngestCheckpoint.save(stage: .passB, schoolID: manifest.id, signature: pdfSignature)

            if let uni = collegePersistence.getActiveUniversity() {
                CatalogIngestPipeline.postCatalogDataDidCommit(
                    universityID: uni.id,
                    reason: "catalog pdf courses+programs committed",
                    archive: CatalogIngestPipeline.ArchivePassRequest(
                        schoolID: manifest.id,
                        schoolName: manifest.name,
                        sourceFormat: "pdf",
                        pdfFileURL: localPDFURL,
                        pdfSHA256: pdfSignature
                    )
                )
            }

            hooks?.onProgress?(0.95, "PDF catalog ingest complete.")
            if totalPDFPages > 0 {
                CatalogMenuBarProgressNotifier.postCountProgress(
                    completed: totalPDFPages,
                    total: totalPDFPages,
                    title: manifest.name,
                    stage: "Pages"
                )
            }
            _ = try? collegePersistence.exportCatalogBundle(for: manifest.name)
            _ = try? CatalogStorePortableBridge.exportSignedCatalogStore(for: manifest.name)
            if let gate = pdfIngestGateOutcome {
                CatalogIngestGate.recordSuccessfulBaseline(gate)
            }
            CatalogBackgroundSyncRunner.setStoredIngestSignature(pdfSignature, schoolID: manifest.id, format: "pdf", depth: depth)
            return .completed(scheduledPassB: false)
        }
    }

    private static func legacyPDFMajorRows(
        programs: [ScrapedProgram],
        requirements: [DegreeRequirement]
    ) -> [(name: String, degreeLevel: String, degreeType: String?, isMinor: Bool, department: String?, url: String?, resolvedDepartment: String?, resolvedCollege: String?, mappingConfidence: Double?, mappingSource: String?, requirements: [DegreeRequirement]?)] {
        programs.map { program in
            let isMinor = program.type.lowercased().contains("minor")
            let degreeTypeTrimmed = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let degreeType = (degreeTypeTrimmed?.isEmpty ?? true) ? nil : degreeTypeTrimmed
            let degreeLevel = DegreeConfiguration.level(for: degreeType ?? "") ?? DegreeConfiguration.undergraduate

            let deptTrimmed = program.department?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dept = (deptTrimmed?.isEmpty ?? true) ? nil : deptTrimmed

            let url = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let requirementsForProgram = requirements.filter {
                $0.major.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(program.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }

            return (
                name: program.name,
                degreeLevel: degreeLevel,
                degreeType: degreeType,
                isMinor: isMinor,
                department: dept,
                url: url,
                resolvedDepartment: nil,
                resolvedCollege: nil,
                mappingConfidence: nil,
                mappingSource: "pdf-block-classifier",
                requirements: requirementsForProgram.isEmpty ? nil : requirementsForProgram
            )
        }
    }

    private static func persistPDFIngestDiagnostics(
        manifest: SchoolManifest,
        pdfSignature: String,
        pageCount: Int,
        programs: Int,
        courses: Int,
        requirements: Int,
        policies: Int,
        healthReport: PDFHealthReport,
        blockClassification: CatalogPDFBlockClassificationDiagnostics?,
        ocrPagesUsed: Int,
        documentIR: CatalogDocumentIR?,
        collegePersistence: CollegePersistence
    ) async {
        var warnings: [String] = []
        if programs == 0 { warnings.append("No programs extracted from PDF.") }
        if courses == 0 { warnings.append("No courses extracted from PDF.") }
        if healthReport.pageCount > 0,
           Double(healthReport.lowTextDensityPages) / Double(healthReport.pageCount) > 0.35 {
            warnings.append("Many pages have low text density; OCR may be required.")
        }
        if let layoutNote = healthReport.layoutNote, !layoutNote.isEmpty {
            warnings.append(layoutNote)
        }
        if let blockClassification {
            if blockClassification.programRejected > 0 {
                warnings.append("Program blocks rejected: \(blockClassification.programRejected) of \(blockClassification.programCandidates) candidates.")
            }
            for sample in blockClassification.sampleRejections.prefix(3) {
                warnings.append("Rejected: \(sample)")
            }
        }

        let layoutProfileID = CatalogPDFIngestPersistence.layoutProfileID(for: manifest, documentIR: documentIR)
        PDFScrapeReport.save(
            PDFScrapeReport(
                schoolID: manifest.id,
                schoolName: manifest.name,
                generatedAt: Date(),
                parserVersion: "2.0.0-pdf-blocks",
                pdfSHA256: pdfSignature,
                pageCount: pageCount,
                programsExtracted: programs,
                coursesExtracted: courses,
                requirementsExtracted: requirements,
                policiesExtracted: policies,
                healthReport: healthReport,
                blockClassification: blockClassification,
                parserCapabilityVersion: CatalogParserCapability.version,
                ocrPagesUsed: ocrPagesUsed,
                averageProgramConfidence: blockClassification?.averageAcceptedProgramConfidence,
                layoutProfileID: layoutProfileID,
                documentIRNodeCount: documentIR?.nodes.count,
                warnings: warnings
            )
        )

        CatalogIngestObservability.record(
            CatalogIngestMetricSample(
                schoolID: manifest.id,
                source: "pdf",
                succeeded: true,
                durationMs: 0,
                pageCount: pageCount,
                ocrPagesUsed: ocrPagesUsed,
                averageProgramConfidence: blockClassification?.averageAcceptedProgramConfidence,
                timestamp: Date(),
                programsFound: programs,
                coursesFound: courses,
                requirementsFound: requirements,
                layoutProfileID: layoutProfileID
            )
        )

        CatalogGoldenFixtureStore.save(
            .init(
                schoolID: manifest.id,
                parserVersion: "2.0.0-pdf-blocks",
                createdAt: Date(),
                programCount: programs,
                courseCount: courses,
                requirementCount: requirements
            )
        )
        if let avg = blockClassification?.averageAcceptedProgramConfidence, avg < 0.65 {
            CatalogReviewQueue.enqueue(
                .init(
                    schoolID: manifest.id,
                    reason: "low program confidence",
                    confidence: avg,
                    createdAt: Date()
                )
            )
        }

        let capabilities = await collegePersistence.catalogCapabilities(universityName: manifest.name)
        let presence = await collegePersistence.catalogPresence(universityName: manifest.name)
        CatalogIntegrityReport.save(
            CatalogIntegrityReport(
                schoolID: manifest.id,
                schoolName: manifest.name,
                generatedAt: Date(),
                coursesInStore: presence.courses,
                programsInStore: presence.majors + presence.minors,
                requirementsInStore: capabilities.requirementsReady ? max(requirements, 1) : requirements,
                academicReady: capabilities.academicReady,
                archiveReady: capabilities.fullArchiveReady,
                vectorsReady: capabilities.vectorsReady,
                warnings: warnings
            )
        )
    }
}

// MARK: - Minimal ingest pipeline signaling (catalogDataDidCommit)

enum CatalogIngestPipeline {
    struct ArchivePassRequest: Sendable {
        let schoolID: String
        let schoolName: String
        let sourceFormat: String
        let pdfFileURL: URL?
        let pdfSHA256: String?
    }

    /// Signals that academic catalog tiers were committed and catalog vectors can rebuild.
    ///
    /// This is intentionally minimal for v1: we post after the existing import flows finish,
    /// so the vector indexer (if/when started) has a reliable “safe point”.
    @MainActor
    static func postCatalogDataDidCommit(
        universityID: UUID,
        reason: String,
        archive: ArchivePassRequest? = nil
    ) {
        CatalogVectorIndexingLifecycle.start()
        NotificationCenter.default.post(
            name: .catalogDataDidCommit,
            object: nil,
            userInfo: [
                "universityID": universityID.uuidString,
                "reason": reason
            ]
        )
        if let archive {
            scheduleFullArchivePass(archive)
        }
    }

    /// Pass B: archive every PDF page (menubar progress only; does not block Academics UI).
    @MainActor
    private static func scheduleFullArchivePass(_ request: ArchivePassRequest) {
        guard request.sourceFormat.lowercased() == "pdf" else { return }
        guard let pdfURL = request.pdfFileURL else { return }
        if CatalogArchiveStore.isArchiveReady(schoolID: request.schoolID) { return }

        let schoolID = request.schoolID
        let pdfSHA = request.pdfSHA256
        Task.detached(priority: .utility) {
            do {
                try CatalogIngestCheckpoint.throwIfCancelled(schoolID: schoolID)
                try await CatalogArchiveStore.archivePDFPages(
                    schoolID: schoolID,
                    pdfURL: pdfURL,
                    pdfSHA256: pdfSHA
                ) { completed, total in
                    CatalogMenuBarProgressNotifier.postCountProgress(
                        completed: completed,
                        total: total,
                        title: request.schoolName,
                        stage: "Archive"
                    )
                }
                CatalogIngestCheckpoint.save(stage: .archive, schoolID: schoolID, signature: pdfSHA)
                await MainActor.run {
                    CatalogMenuBarProgressNotifier.postSucceeded(
                        title: String(
                            localized: "catalog.archive.complete",
                            defaultValue: "Catalog archive complete"
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    CatalogMenuBarProgressNotifier.postFailed(message: error.localizedDescription)
                }
            }
        }
    }
}
