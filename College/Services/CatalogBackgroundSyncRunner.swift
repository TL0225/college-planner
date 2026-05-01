import Foundation
import os

/// Shared ModernCampus / GitHub catalog sync used from onboarding, Settings, and the menu bar.
@MainActor
enum CatalogBackgroundSyncRunner {
    private static let poiLog = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)

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

    /// `light`: program index only (fast onboarding). `full`: scrape degree requirements for every program (heavy).
    enum CatalogSyncDepth: Sendable {
        case light
        case full
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

        let cached = githubService.loadCachedSchoolsList() ?? []
        if let found = matchSchoolManifest(named: normalizedTarget, in: cached) {
            return found
        }

        let fetched = try await githubService.fetchSchoolsList()
        try? githubService.cacheSchoolsList(fetched)

        if let found = matchSchoolManifest(named: normalizedTarget, in: fetched) {
            return found
        }

        throw GitHubError.invalidData
    }

    /// Phase A indexes programs (and optionally full requirement pages); Phase B imports courses in a detached task. Returns `true` when Phase B was scheduled.
    static func runModernCampusCatalogSync(
        manifest: SchoolManifest,
        toastID: UUID,
        coreDataManager: CoreDataManager,
        notifications: AppNotificationCenter,
        githubService: GitHubDataService,
        depth: CatalogSyncDepth = .light,
        hooks: Hooks?
    ) async throws -> Bool {
        let syncSignpost = OSSignpostID(log: poiLog)
        os_signpost(.begin, log: poiLog, name: "CatalogSync.Run", signpostID: syncSignpost)
        defer { os_signpost(.end, log: poiLog, name: "CatalogSync.Run", signpostID: syncSignpost) }

        let catalogURL = (manifest.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else {
            throw ScraperError.invalidURL
        }

        notifications.update(id: toastID, message: "Discovering catalogs…", progress: 0.2)
        hooks?.onVisualPhase?(.discovering)
        hooks?.onProgress?(0.2, "Discovering ModernCampus catalogs...")

        let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
        guard let baseURL = URL(string: normalizedCatalogURL) else {
            throw ScraperError.invalidURL
        }

        let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []
        let reducedDiscovered = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: discovered)
        let catalogsToScrape: [ModernCampusCatalogDescriptor]
        if !reducedDiscovered.isEmpty {
            catalogsToScrape = reducedDiscovered
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

        var programsByCatalogAndURL: [String: ScrapedProgram] = [:]
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

            let programScraper = UniversalCatalogScraper()
            let catalogIDInt = Int(catalog.catoid) ?? 0
            let scrapedPrograms = try await programScraper.scrapeAllPrograms(
                baseURL: baseURL,
                catalogID: catalogIDInt
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
            os_signpost(.end, log: poiLog, name: "CatalogSync.Catalog", signpostID: catalogSignpost)
        }

        let programs = Array(programsByCatalogAndURL.values)

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

        try await coreDataManager.importSchoolCatalog(emptyProfile)

        var departmentToGroup: [String: String] = [:]
        for (dedupKey, program) in programsByCatalogAndURL {
            let department = (program.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !department.isEmpty else { continue }

            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let catalogLabel = catalogMeta.map {
                ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid)
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
            try coreDataManager.saveDepartments(rows, for: manifest.name)
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
            sourceCatalogCatoid: String
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
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?
        ) {
            let trimmedCatoid = sourceCatalogCatoid.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawProgramURL = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlForStorage: String? = {
                guard !rawProgramURL.isEmpty else { return nil }
                guard !trimmedCatoid.isEmpty else { return rawProgramURL }
                return acalogURLForcingCatoid(rawProgramURL, catoid: trimmedCatoid)
            }()

            let normalizedType = program.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawDegreeType = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDegreeType = (rawDegreeType ?? "").lowercased()

            let isCredentialLike = normalizedType.contains("certificate") ||
                normalizedType.contains("credential") ||
                normalizedDegreeType.contains("certificate") ||
                normalizedDegreeType.contains("credential")
            // Minors-only flag: certificates/micro-credentials stay `isMinor == false` but keep explicit `degreeType`
            // so UI and resolution can include them in the "secondary program" bucket via predicates.
            let isMinor = normalizedType.contains("minor") && !isCredentialLike

            let degreeType: String?
            if let rawDegreeType, !rawDegreeType.isEmpty {
                degreeType = rawDegreeType
            } else if normalizedType.contains("certificate") {
                degreeType = "Certificate"
            } else if normalizedType.contains("credential") {
                degreeType = "Credential"
            } else if isMinor {
                degreeType = "Minor"
            } else {
                degreeType = nil
            }

            return (
                name: program.name,
                degreeLevel: catalogDegreeLevel,
                degreeType: degreeType,
                isMinor: isMinor,
                department: program.department,
                url: urlForStorage,
                resolvedDepartment: program.department,
                resolvedCollege: program.college,
                mappingConfidence: nil as Double?,
                mappingSource: "onboarding.moderncampus",
                requirements: program.requirements,
                sourceCatalogCatoid: sourceCatalogCatoid
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
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?
        )] = []

        for (dedupKey, program) in programsByCatalogAndURL.sorted(by: { $0.key < $1.key }) {
            let catoidFromKey = dedupKey.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            let catalogMeta = catalogsToScrape.first { $0.catoid == catoidFromKey }
            let bucket = catalogMeta.map { ModernCampusCatalogLabels.normalizedCatalogTypeLabel(from: $0.title, catoid: $0.catoid) }
                ?? "Catalog \(catoidFromKey)"
            rows.append(saveRow(program: program, catalogDegreeLevel: bucket, sourceCatalogCatoid: catoidFromKey))
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
                        requirements: nil as [DegreeRequirement]?,
                        sourceCatalogCatoid: nil as String?
                    )
                }
            }
        }

        if !rows.isEmpty {
            try coreDataManager.saveMajors(rows, for: manifest.name)
        }

        let catoidSummary = catalogsToScrape.map(\.catoid).joined(separator: ",")
        let programsWithRequirements = rows.filter { row in
            guard let reqs = row.requirements else { return false }
            return !reqs.isEmpty
        }.count
        DebugLogger.shared.log(
            "📊 Catalog sync Phase A — catoids=[\(catoidSummary)] programs=\(programs.count) savedRows=\(rows.count) nonemptyRequirements=\(programsWithRequirements) depth=\(depth == .full ? "full" : "light")"
        )

        _ = coreDataManager.setActiveUniversity(named: manifest.name)

        clearModernCampusCachesIfAvailable()

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

        let dataManager = coreDataManager
        let notify = notifications
        let catalogsCopy = catalogsToScrape
        let manifestCopy = manifest
        let normalizedURLCopy = normalizedCatalogURL
        let recordDeepScrapeDone = (depth == .full)

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

            func normalizeCourseCode(_ raw: String) -> String {
                raw
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
            }

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
                var coursesByCode: [String: CatalogCourse] = [:]
                var perCatalogCourseRows: [(catoid: String, title: String, course: CatalogCourse)] = []
                let total = max(1, catalogsCopy.count)

                for (index, catalog) in catalogsCopy.enumerated() {
                    let frac = 0.05 + (0.85 * Double(index + 1) / Double(total))
                    NotificationCenter.default.post(
                        name: .collegeCatalogBackgroundImportProgress,
                        object: nil,
                        userInfo: [
                            "fraction": frac,
                            "title": "Courses: \(catalog.title)",
                            "finished": false
                        ]
                    )

                    let baseURL = normalizedURLCopy
                    let catoid = catalog.catoid
                    let scrapedCourses = try await Task.detached(priority: .utility) {
                        try await ModernCampusEngine.fetchAllCourses(
                            baseURL: baseURL,
                            catoid: catoid
                        )
                    }.value
                    if !recordDeepScrapeDone {
                        for course in scrapedCourses {
                            perCatalogCourseRows.append((catoid: catalog.catoid, title: catalog.title, course: course))
                        }
                    }
                    for course in scrapedCourses {
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
                    clearModernCampusCachesIfAvailable()
                }

                let courses = Array(coursesByCode.values)

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
                    clearModernCampusCachesIfAvailable()

                    if recordDeepScrapeDone {
                        UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey)
                    }

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

        return true
    }

    /// Start or restart catalog sync for the user’s school (Settings / menu bar / Overview). Safe to call when not onboarding.
    static func runUserInitiatedCatalogSync(
        schoolName: String,
        coreDataManager: CoreDataManager,
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
            #if os(macOS)
            CatalogMenuBarProgressNotifier.postFinished()
            #endif
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

        #if os(macOS)
        CatalogMenuBarProgressNotifier.postInProgress(
            fraction: 0,
            title: String(localized: "catalog.sync.menubar_starting", defaultValue: "Starting catalog sync…"),
            indeterminate: true
        )
        #endif

        let toastID = notifications.post(
            kind: .progress,
            title: String(localized: "catalog.sync.toast_title", defaultValue: "Catalog Sync"),
            message: String(format: String(localized: "catalog.sync.resolving_fmt", defaultValue: "Resolving %@…"), trimmed),
            progress: 0.05,
            isDismissible: true
        )

        do {
            notifications.update(id: toastID, message: String(localized: "catalog.sync.loading_manifest", defaultValue: "Loading school manifest…"), progress: 0.15)
            #if os(macOS)
            CatalogMenuBarProgressNotifier.postInProgress(
                fraction: 0.12,
                title: String(localized: "catalog.sync.menubar_manifest", defaultValue: "Loading school manifest…"),
                indeterminate: false
            )
            #endif

            let manifest = try await resolveSchoolManifest(named: trimmed, githubService: githubService)
            let canonicalSchoolName = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)

            let format = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let shouldRunModernCampusScraper = format == "acalog" || format == "moderncampus"

            var scheduledBackgroundCourseImport = false
            if shouldRunModernCampusScraper {
                #if os(macOS)
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
                scheduledBackgroundCourseImport = try await runModernCampusCatalogSync(
                    manifest: manifest,
                    toastID: toastID,
                    coreDataManager: coreDataManager,
                    notifications: notifications,
                    githubService: githubService,
                    depth: depth,
                    hooks: menuBarHooks
                )
                #else
                scheduledBackgroundCourseImport = try await runModernCampusCatalogSync(
                    manifest: manifest,
                    toastID: toastID,
                    coreDataManager: coreDataManager,
                    notifications: notifications,
                    githubService: githubService,
                    depth: depth,
                    hooks: nil
                )
                #endif
            } else {
                notifications.update(id: toastID, message: String(localized: "catalog.sync.discovering_profile", defaultValue: "Discovering catalog profile…"), progress: 0.2)
                #if os(macOS)
                CatalogMenuBarProgressNotifier.postInProgress(
                    fraction: 0.25,
                    title: String(localized: "catalog.sync.menubar_downloading_profile", defaultValue: "Downloading school profile…"),
                    indeterminate: false
                )
                #endif
                let profile = try await githubService.downloadSchoolProfile(schoolID: manifest.id)

                notifications.update(id: toastID, message: String(localized: "catalog.sync.importing", defaultValue: "Importing catalog to local database…"), progress: 0.75)
                #if os(macOS)
                CatalogMenuBarProgressNotifier.postInProgress(
                    fraction: 0.75,
                    title: String(localized: "catalog.sync.menubar_importing_db", defaultValue: "Importing catalog to database…"),
                    indeterminate: false
                )
                #endif
                try await coreDataManager.importSchoolCatalog(profile)
                _ = coreDataManager.setActiveUniversity(named: canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName)
                if depth == .full {
                    UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey)
                }
            }

            if !scheduledBackgroundCourseImport {
                UserDefaults.standard.set(false, forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey)
                #if os(macOS)
                CatalogMenuBarProgressNotifier.postFinished()
                #endif
            }

            let readyLabel = canonicalSchoolName.isEmpty ? trimmed : canonicalSchoolName
            notifications.complete(
                id: toastID,
                kind: .success,
                title: String(localized: "catalog.sync.ready_title", defaultValue: "Catalog Ready"),
                message: String(format: String(localized: "catalog.sync.ready_body_fmt", defaultValue: "%@ is synced and ready."), readyLabel),
                autoDismissAfter: 4
            )
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
            #if os(macOS)
            CatalogMenuBarProgressNotifier.postFinished()
            #endif
        }
    }
}
