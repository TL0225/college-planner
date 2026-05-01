import Foundation
import os
import SwiftSoup

/// A robust, stateful scraper that reads Acalog pages linearly to associate
/// headers (Colleges/Departments) with the links (Programs) that follow them.
nonisolated struct HierarchyItem: Hashable, Sendable {
    let programName: String
    let programURL: String
    let programType: String // "Major", "Minor", "Certificate", etc.
    let college: String?
    let department: String?
    let degreeType: String? // BS, BA, MS, etc.
}

actor UniversalCatalogScraper {
    struct ProgramRequirementsDiagnostics: Sendable, Equatable {
        let signature: String
        let usedMajorRequirementsSection: Bool
        let categoriesFound: Int
        let requiredCourseCount: Int
        let selectCourseCount: Int
        let uniqueCourseCount: Int
    }
    
    // MARK: - Dynamic Mappings
    // Department-to-college mapping built dynamically from catalog structure
    private var departmentToCollegeMapping: [String: String] = [:]
    // Normalized-key to canonical department name
    private var canonicalDepartmentNameByKey: [String: String] = [:]

    // MARK: - Program Ownership Overrides (UB-specific)
    /// ProgramURL -> (canonicalDepartment, college/school)
    ///
    /// For UB, department entity pages (preview_entity.php) often list majors/minors
    /// more reliably than individual program pages expose ownership text.
    private var programOwnershipOverridesByURL: [String: (department: String, college: String)] = [:]
    /// UB-only: program URL -> display name (from preview_entity pages).
    /// This lets us include programs that are not listed on majors/minors container pages.
    private var programNameByURL: [String: String] = [:]
    
    // MARK: - Course Catalog Cache
    /// Course code -> full course details (scraped from Courses catalog page)
    /// This serves as a backup data source when extracting course details from program requirement pages.
    private var courseDetailsByCode: [String: CourseDetail] = [:]

    // MARK: - Ownership Extraction Cache
    /// Per-run cache for program ownership extraction from program detail pages.
    /// Keyed by canonicalized preview_program URL.
    private var ownershipByProgramURLCache: [String: (department: String?, college: String?)] = [:]

    nonisolated private static func normalizeCourseCodeForLookup(_ raw: String) -> String? {
        let s = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

          // ModernCampus course codes often include a section/type suffix after the digits
          // (e.g., "AAP 503SEM", "MTH 141LEC"). Our requirement parser normalizes to "SUBJ 123"
          // (or "SUBJ 501" for 4-digit catalogs), so we strip any suffix here.
          guard let re = Self.cachedRegex("\\b([A-Z]{2,6})\\s*(\\d{2,4})(?:[A-Z]{0,6})\\b") else { return nil }
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
              m.numberOfRanges >= 3,
              let subjRange = Range(m.range(at: 1), in: s),
              let numRange = Range(m.range(at: 2), in: s)
        else { return nil }

        let subj = String(s[subjRange])
        let num = String(s[numRange])
        return "\(subj) \(num)"
    }

    /// Build a course detail cache using ModernCampusEngine's robots-compliant course crawler.
    /// This crawls the Course Descriptions index (across pagination) and then fetches each preview page
    /// (equivalent to clicking each course row in the UI).
    private func buildCourseCatalogCache(baseURL: URL, catalogID: Int) async throws {
        let logger = DebugLogger.shared
        logger.logSection("📚 BUILDING COURSE CATALOG CACHE")

        guard let host = baseURL.host, let scheme = baseURL.scheme else {
            throw ScraperError.invalidURL
        }
        let base = "\(scheme)://\(host)"

        let courses = try await ModernCampusEngine.fetchAllCourses(baseURL: base, catoid: String(catalogID))
        logger.log("📚 Courses(content): returned \(courses.count) CatalogCourse rows")

        var inserted = 0
        for course in courses {
            guard let key = Self.normalizeCourseCodeForLookup(course.courseCode) else { continue }
            let incoming = CourseDetail(
                code: key,
                title: course.title,
                credits: course.credits > 0 ? String(course.credits) : nil
            )

            if let existing = courseDetailsByCode[key] {
                // Prefer non-nil/non-zero credits and longer titles.
                let existingCredits = existing.credits?.trimmingCharacters(in: .whitespacesAndNewlines)
                let incomingCredits = incoming.credits?.trimmingCharacters(in: .whitespacesAndNewlines)
                let shouldReplaceCredits = (existingCredits == nil || existingCredits == "0") && (incomingCredits != nil && incomingCredits != "0")
                let shouldReplaceTitle = (existing.title == nil || (existing.title?.count ?? 0) < (incoming.title?.count ?? 0))

                if shouldReplaceCredits || shouldReplaceTitle {
                    courseDetailsByCode[key] = CourseDetail(
                        code: key,
                        title: shouldReplaceTitle ? incoming.title : existing.title,
                        credits: shouldReplaceCredits ? incoming.credits : existing.credits
                    )
                }
            } else {
                courseDetailsByCode[key] = incoming
                inserted += 1
                if inserted <= 10 {
                    let t = incoming.title ?? "no title"
                    let c = incoming.credits ?? "no credits"
                    logger.log("   📝 Cached: \(incoming.code) - \(t) (\(c) cr)")
                }
            }
        }

        logger.log("✅ Course catalog cache ready: \(courseDetailsByCode.count) unique normalized courses")
    }
    
    // MARK: - Regex Toolkit
    nonisolated private struct RegexKey: Hashable {
        let pattern: String
        let options: NSRegularExpression.Options.RawValue
    }

    nonisolated(unsafe) private static var regexCache: [RegexKey: NSRegularExpression] = [:]
    // OSAllocatedUnfairLock is non-blocking — avoids thread-pool starvation under high concurrency.
    nonisolated(unsafe) private static var regexCacheLock = OSAllocatedUnfairLock()

    nonisolated private static func cachedRegex(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = RegexKey(pattern: pattern, options: options.rawValue)
        if let cached = regexCacheLock.withLock({ regexCache[key] }) {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCacheLock.withLock { regexCache[key] = regex }
        return regex
    }
    // Broad patterns to identify organizational units
    private let collegePatterns = [
        "(?i).*(College|School|Faculty) of.*",
        "(?i)^College of .*",
        "(?i)^School of .*",
        "(?i)^The College of .*",
        "(?i)^The School of .*"
    ]
    
    private let departmentPatterns = [
        "(?i).*(Department|Division|Program) of.*",
        "(?i)^Department of .*",
        "(?i)^Division of .*"
    ]
    
    private let programLinkPattern = "preview_program.php"

    /// Many ModernCampus/Acalog catalogs emit links like `content.php?navoid=...` or
    /// `preview_program.php?poid=...` that rely on server-side session state for `catoid`.
    /// Our scraper does not maintain that session state, so we must make `catoid` explicit.
    ///
    /// IMPORTANT: We *force* the provided `catalogID` (replace if present). This prevents
    /// cross-catalog contamination where a link points at the wrong catoid (or a server
    /// default catoid), which would cause undergrad content to appear under graduate, etc.
    nonisolated private static func forceCatoid(_ urlString: String, catalogID: Int) -> String {
        let cleaned = sanitizeAcalogURLString(urlString)
        guard !cleaned.isEmpty, var comps = URLComponents(string: cleaned) else { return cleaned.isEmpty ? urlString : cleaned }
        var items = comps.queryItems ?? []
        items.removeAll(where: { $0.name.lowercased() == "catoid" })
        items.append(URLQueryItem(name: "catoid", value: String(catalogID)))
        comps.queryItems = items
        return comps.string ?? cleaned
    }

    /// Normalize an absolute URL to the scheme/host of a base URL.
    /// This helps when a catalog can be accessed via multiple equivalent hosts
    /// (e.g., `catalog.buffalo.edu` vs `catalogs.buffalo.edu`).
    nonisolated private static func normalizeToBaseHost(_ urlString: String, baseURL: URL) -> String {
        let cleaned = sanitizeAcalogURLString(urlString)
        guard !cleaned.isEmpty, var comps = URLComponents(string: cleaned) else { return cleaned.isEmpty ? urlString : cleaned }
        guard comps.host != nil else { return cleaned }
        if let scheme = baseURL.scheme { comps.scheme = scheme }
        if let host = baseURL.host { comps.host = host }
        return comps.string ?? cleaned
    }

    // MARK: - URL Canonicalization

    /// Some scraped hrefs can contain embedded whitespace/newlines (e.g. CSV line breaks or
    /// HTML pretty-printing). These break URLComponents parsing and, worse, can cause ownership
    /// overrides to miss. For identity/matching we treat any raw whitespace as non-semantic.
    nonisolated private static func sanitizeAcalogURLString(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Acalog often emits multiple URL variants for the same logical entity/program
    /// (e.g., different `returnto=` values). We canonicalize URLs so we can:
    /// - de-dupe programs deterministically
    /// - match UB ownership overrides reliably
    nonisolated private static func canonicalizeProgramURL(_ urlString: String) -> String {
        canonicalizeAcalogURL(urlString, removingQueryItems: ["returnto"])
    }

    nonisolated private static func canonicalizeEntityURL(_ urlString: String) -> String {
        canonicalizeAcalogURL(urlString, removingQueryItems: ["returnto"])
    }

    nonisolated private static func canonicalizeAcalogURL(_ urlString: String, removingQueryItems: Set<String>) -> String {
        let cleaned = sanitizeAcalogURLString(urlString)
        guard var components = URLComponents(string: cleaned) else { return cleaned.isEmpty ? urlString : cleaned }

        if let items = components.queryItems, !items.isEmpty {
            let filtered = items
                .filter { !removingQueryItems.contains($0.name.lowercased()) }
                .sorted {
                    let aName = $0.name.lowercased()
                    let bName = $1.name.lowercased()
                    if aName != bName { return aName < bName }
                    let aVal = ($0.value ?? "").lowercased()
                    let bVal = ($1.value ?? "").lowercased()
                    return aVal < bVal
                }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Fragments like "#core_123" should not affect identity or matching.
        components.fragment = nil

        // URLComponents may leave a trailing '?' when queryItems=nil.
        var rebuilt = components.string ?? cleaned
        if rebuilt.hasSuffix("?") { rebuilt.removeLast() }
        return rebuilt
    }

    /// UB-specific ownership refinement.
    ///
    /// Some UB pages only identify ownership at the school level (e.g. "School of Management"),
    /// and some listings provide no headings. In those cases, ownership can be overly generic
    /// or (rarely) inherit an adjacent department label.
    ///
    /// Keep this conservative: only infer department from a high-signal prefix when we already
    /// know we're within the School of Management context.
    private func refineUBOwnership(programName: String, department: String?, college: String?) -> (department: String?, college: String?) {
        let name = programName.normalizedCatalogText()
        let dept = (department ?? "").normalizedCatalogText()
        let col = (college ?? "").normalizedCatalogText()

        let deptLower = dept.lowercased()
        let colLower = col.lowercased()

        let inSOM = deptLower.contains("school of management") || colLower.contains("school of management")
        guard inSOM else { return (department, college) }

        // Only refine when ownership is at the school level (i.e. department == college).
        // If we have an explicit h4 department (e.g. "Accounting and Law"), keep it.
        let deptIsSchoolLevel = deptLower.isEmpty || deptLower == colLower || deptLower.contains("school of management")
        guard deptIsSchoolLevel else { return (department, college) }

        // Example: "Accounting BS/Accounting MS" should map to Accounting.
        let lead = name
            .components(separatedBy: CharacterSet(charactersIn: ",/(-)"))
            .first?
            .normalizedCatalogText() ?? ""

        // Handle common degree suffixes like "Accounting BS" or combined titles like
        // "Accounting BS/Accounting MS".
        if lead.lowercased().hasPrefix("accounting") {
            let key = normalizeDepartmentKey(lead)
            let canonical = canonicalDepartmentNameByKey[key] ?? "Accounting"
            let fixedCollege: String? = col.isEmpty ? "School of Management" : college
            return (department: canonical, college: fixedCollege)
        }

        return (department, college)
    }
    
    // MARK: - Public API

    private func resetRunScopedState() {
        departmentToCollegeMapping.removeAll(keepingCapacity: true)
        canonicalDepartmentNameByKey.removeAll(keepingCapacity: true)
        programOwnershipOverridesByURL.removeAll(keepingCapacity: true)
        programNameByURL.removeAll(keepingCapacity: true)
        courseDetailsByCode.removeAll(keepingCapacity: true)
        ownershipByProgramURLCache.removeAll(keepingCapacity: true)
    }
    
    /// The main entry point. Probes the sidebar, finds relevant pages, and scrapes them.
    func scrapeAllPrograms(baseURL: URL, catalogID: Int) async throws -> [ScrapedProgram] {
        let logger = DebugLogger.shared
        logger.logSection("🌍 UNIVERSAL SCRAPER STARTED")
        logger.log("🎯 Target: \(baseURL.absoluteString)")
        logger.log("📋 Catalog ID: \(catalogID)")

        // Ensure no stale state leaks across runs/campuses.
        resetRunScopedState()
        
        // 0. Build course cache (robots-compliant) so requirement parsing can fill missing credits/titles.
        do {
            try await buildCourseCatalogCache(baseURL: baseURL, catalogID: catalogID)
        } catch {
            logger.log("⚠️ Course catalog cache build failed (non-fatal): \(error)")
        }
        
        // 1. Build department-to-college mapping (for universities that have this structure)
        try await buildDepartmentToCollegeMapping(baseURL: baseURL, catalogID: catalogID)

        // 1b. UB-only: build program ownership overrides from department entity pages.
        // This gives us deterministic (department, college) for program URLs even when
        // the program page doesn't include ownership text.
        if baseURL.host?.contains("buffalo.edu") == true {
            do {
                try await buildProgramOwnershipOverridesFromDepartmentEntities(baseURL: baseURL, catalogID: catalogID)
                logger.log("🧭 Built program ownership overrides (UB): \(programOwnershipOverridesByURL.count)")
            } catch {
                logger.log("⚠️ Failed building UB program ownership overrides: \(error)")
            }
        }
        
        // 2. Probe Sidebar for "Container" pages (Degrees, Majors, Departments)
        let containerLinks = try await probeSidebarForContainers(baseURL: baseURL, catalogID: catalogID)
        logger.log("🔍 Found \(containerLinks.count) potential container pages:")
        for link in containerLinks {
            logger.log("   • \(link.text)")
        }
        
        var allItems = Set<HierarchyItem>()

        // 2. Scrape container pages concurrently (max 4 simultaneous) to parallelize network I/O.
        let containerSemaphore = ModernCampusEngine.AsyncSemaphore(value: 4)
        try await withThrowingTaskGroup(of: (String, [HierarchyItem]).self) { group in
            for containerLink in containerLinks {
                group.addTask { [containerLink] in
                    await containerSemaphore.acquire()
                    defer { containerSemaphore.release() }
                    let items = try await self.scrapeStream(
                        url: containerLink.href,
                        defaultContext: containerLink.text,
                        catalogID: catalogID
                    )
                    return (containerLink.text, items)
                }
            }
            for try await (name, items) in group {
                allItems.formUnion(items)
                logger.log("   ✓ Found \(items.count) programs in \(name)")
            }
        }

        // 2b. UB-only: include programs discovered on preview_entity pages even if they don't
        // appear on majors/minors container pages.
        if baseURL.host?.contains("buffalo.edu") == true {
            let existingProgramURLs = Set(allItems.map { $0.programURL })
            let before = allItems.count
            for (url, name) in programNameByURL {
                // Only inject programs that are not already present from container pages.
                if existingProgramURLs.contains(url) { continue }
                guard let owner = programOwnershipOverridesByURL[url] else { continue }

                let inferred = inferProgramTypeAndDegreeType(from: name, contextHint: nil)
                let item = HierarchyItem(
                    programName: inferred.cleanedName,
                    programURL: url,
                    programType: inferred.programType,
                    college: owner.college,
                    department: owner.department,
                    degreeType: inferred.degreeType
                )
                allItems.insert(item)
            }
            let added = max(0, allItems.count - before)
            if added > 0 {
                logger.log("🧩 UB: added \(added) programs from department entity pages")
            }
        }
        
        logger.log("✅ Total unique programs found: \(allItems.count)")

        // MARK: - Full debug dump (requested)
        // DebugLogger writes to Desktop and has no size cap; this can be large but is intentional.
        do {
            func displayName(for item: HierarchyItem) -> String {
                // Combined degrees already include degree credentials (e.g., "BS/MS") in the name.
                if item.programType == "Combined Degree" { return item.programName }
                if item.programName.contains("/") { return item.programName }
                if item.programType == "Major", let dt = item.degreeType, !dt.isEmpty {
                    // Match the catalog style: "Accounting BS".
                    return "\(item.programName) \(dt)"
                }
                return item.programName
            }

            let schoolsFromMapping = Set(departmentToCollegeMapping.values)
            let schoolsFromPrograms = Set(allItems.compactMap { $0.college?.normalizedCatalogText() }.filter { !$0.isEmpty })
            let allSchools = Array(schoolsFromMapping.union(schoolsFromPrograms)).sorted()

            let departmentsFromMapping = Array(Set(departmentToCollegeMapping.keys)).sorted()
            let departmentsFromPrograms = Array(Set(allItems.compactMap { $0.department?.normalizedCatalogText() }.filter { !$0.isEmpty })).sorted()

            let majors = allItems.filter { $0.programType == "Major" }.map(displayName).sorted()
            let minors = allItems.filter { $0.programType == "Minor" }.map(displayName).sorted()
            let combined = allItems.filter { $0.programType == "Combined Degree" }.map(displayName).sorted()
            let certificates = allItems.filter { $0.programType == "Certificate" }.map(displayName).sorted()
            let masters = allItems.filter { $0.programType == "Master's" }.map(displayName).sorted()
            let doctorates = allItems.filter { $0.programType == "Doctorate" }.map(displayName).sorted()

            let missingCollege = allItems.filter { ($0.college?.normalizedCatalogText().isEmpty ?? true) }
            let missingDepartment = allItems.filter { ($0.department?.normalizedCatalogText().isEmpty ?? true) }

            logger.logSection("UNIVERSAL SCRAPER FULL SUMMARY")
            logger.log("Totals: programs=\(allItems.count), majors=\(majors.count), combined=\(combined.count), minors=\(minors.count), certificates=\(certificates.count), masters=\(masters.count), doctorates=\(doctorates.count)")
            logger.log("Schools/Colleges: mapping=\(schoolsFromMapping.count), programs=\(schoolsFromPrograms.count), union=\(allSchools.count)")
            logger.log("Departments: mapping=\(departmentsFromMapping.count), programs=\(departmentsFromPrograms.count)")
            logger.log("Missing ownership fields: missingCollege=\(missingCollege.count), missingDepartment=\(missingDepartment.count)")

            logger.logSection("SCHOOLS / COLLEGES (\(allSchools.count))")
            for s in allSchools { logger.log("• \(s)") }

            logger.logSection("DEPARTMENTS (DIRECTORY MAP) (\(departmentsFromMapping.count))")
            for d in departmentsFromMapping { logger.log("• \(d)") }

            logger.logSection("DEPARTMENTS (FROM PROGRAMS) (\(departmentsFromPrograms.count))")
            for d in departmentsFromPrograms { logger.log("• \(d)") }

            logger.logSection("MAJORS (\(majors.count))")
            for m in majors { logger.log("• \(m)") }

            logger.logSection("COMBINED DEGREES (\(combined.count))")
            for c in combined { logger.log("• \(c)") }

            logger.logSection("MINORS (\(minors.count))")
            for m in minors { logger.log("• \(m)") }

            if !certificates.isEmpty {
                logger.logSection("CERTIFICATES (\(certificates.count))")
                for c in certificates { logger.log("• \(c)") }
            }

            if !masters.isEmpty {
                logger.logSection("MASTER'S PROGRAMS (\(masters.count))")
                for m in masters { logger.log("• \(m)") }
            }

            if !doctorates.isEmpty {
                logger.logSection("DOCTORATE PROGRAMS (\(doctorates.count))")
                for d in doctorates { logger.log("• \(d)") }
            }

            if !missingCollege.isEmpty || !missingDepartment.isEmpty {
                logger.logSection("PROGRAMS MISSING COLLEGE/DEPARTMENT")
                for item in allItems.sorted(by: { $0.programName < $1.programName }) {
                    let c = item.college?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let d = item.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !c.isEmpty && !d.isEmpty { continue }
                    logger.log("• \(displayName(for: item)) [type=\(item.programType)] college=\(c.isEmpty ? "nil" : c) dept=\(d.isEmpty ? "nil" : d) url=\(item.programURL)")
                }
            }
        }
        
        // Show sample programs for debugging
        logger.log("📊 Sample programs:")
        for item in allItems.prefix(5) {
            logger.log("   • \(item.programName) (\(item.programType))")
            logger.log("      URL: \(item.programURL)")
            logger.log("      College: \(item.college ?? "nil")")
            logger.log("      Department: \(item.department ?? "nil")")
        }
        
        // 3. Fetch requirements for each program (batched/concurrent)
        logger.log("📚 Fetching requirements for \(allItems.count) programs...")
        var programsWithRequirements: [ScrapedProgram] = []
        let itemsArray = Array(allItems)

        actor RequirementsLogLimiter {
            private var remaining: Int
            init(max: Int) { self.remaining = max }
            func shouldLog() -> Bool {
                guard remaining > 0 else { return false }
                remaining -= 1
                return true
            }
        }

        let requirementsLogLimiter = RequirementsLogLimiter(max: 20)
        
        // Replace fixed-batch stride with a single TaskGroup gated by an AsyncSemaphore.
        // This keeps up to 8 network requests in-flight at all times without serializing on the
        // actor — idle worker slots are filled immediately rather than waiting for an entire
        // batch stride to finish before starting the next one.
        let semaphore = ModernCampusEngine.AsyncSemaphore(value: 8)
        await withTaskGroup(of: (HierarchyItem, [DegreeRequirement]?).self) { group in
            for item in itemsArray {
                group.addTask {
                    await semaphore.acquire()
                    defer { semaphore.release() }
                    do {
                        // scrapeProgramRequirements is nonisolated: the expensive network
                        // fetch and HTML parse run off the actor's executor in parallel.
                        let reqs = try await self.scrapeProgramRequirements(programURL: item.programURL)
                        return (item, reqs.isEmpty ? nil : reqs)
                    } catch {
                        if await requirementsLogLimiter.shouldLog() {
                            logger.log("⚠️ Requirements scrape failed: \(item.programURL) — \(error)")
                        }
                        return (item, nil)
                    }
                }
            }

            var completedCount = 0
            for await (item, reqs) in group {
                let stampedReqs: [DegreeRequirement]? = reqs.map { requirements in
                    let degreeLabel = item.degreeType ?? item.programType
                    return requirements.map { $0.stamping(major: item.programName, degreeType: degreeLabel) }
                }
                programsWithRequirements.append(
                    ScrapedProgram(
                        name: item.programName,
                        type: item.programType,
                        url: item.programURL,
                        department: item.department,
                        college: item.college,
                        degreeType: item.degreeType,
                        requirements: stampedReqs
                    )
                )
                completedCount += 1
                if completedCount % 10 == 0 || completedCount == itemsArray.count {
                    let reqCount = programsWithRequirements.filter { $0.requirements != nil }.count
                    logger.log("   ✓ \(completedCount)/\(itemsArray.count) programs processed (\(reqCount) with requirements)")
                }
            }
        }
        
        let programs = programsWithRequirements
        
        return programs
    }

    // MARK: - Program Requirements (on-demand)

    /// Scrape course requirements from a program detail page.
    ///
    /// `nonisolated` so that TaskGroup workers perform the expensive network fetch and HTML
    /// parse off the actor's serial executor, enabling true concurrent scraping.
    /// Only the final `enhanceRequirementsWithCatalogData` call hops back to the actor.
    nonisolated func scrapeProgramRequirements(programURL: String) async throws -> [DegreeRequirement] {
        let result = try await scrapeProgramRequirementsWithDiagnostics(programURL: programURL)
        
        // Hop back to actor for the catalog cache lookup (actor-isolated state).
        let enhancedRequirements = await enhanceRequirementsWithCatalogData(result.requirements)
        
        return enhancedRequirements
    }

    /// Fetches and parses a program requirements page.
    /// `nonisolated` — accesses no actor state, so it runs freely off the actor's executor.
    nonisolated func scrapeProgramRequirementsWithDiagnostics(programURL: String) async throws -> (requirements: [DegreeRequirement], diagnostics: ProgramRequirementsDiagnostics) {
        let logger = DebugLogger.shared
        logger.scraper("📄 Requirements page fetch: \(programURL)")

        let html = try await ModernCampusEngine.fetchHTMLPublic(programURL)

        // autoreleasepool prevents SwiftSoup DOM trees from accumulating in memory
        // when this function is called concurrently across many TaskGroup workers.
        let doc: Document = try autoreleasepool {
            try SwiftSoup.parse(html, programURL)
        }

        return try Self.parseProgramRequirementsWithDiagnostics(from: doc, logger: logger)
    }

    nonisolated static func invoke_parseProgramRequirementsHTML_forTests(_ html: String, baseURL: String) throws -> (requirements: [DegreeRequirement], diagnostics: ProgramRequirementsDiagnostics) {
        let doc = try SwiftSoup.parse(html, baseURL)
        return try Self.parseProgramRequirementsWithDiagnostics(from: doc, logger: DebugLogger.shared)
    }

    nonisolated private static func parseProgramRequirementsWithDiagnostics(from doc: Document, logger: DebugLogger) throws -> (requirements: [DegreeRequirement], diagnostics: ProgramRequirementsDiagnostics) {

        func normalizedHeading(_ raw: String) -> String {
            raw.normalizedCatalogText().lowercased()
        }

        func isRequirementsSectionStart(_ heading: String) -> Bool {
            let h = normalizedHeading(heading)
            return h == "course requirements"
                || h == "major requirements"
                || h == "requirements"
                || h == "degree requirements"
                || h == "undergraduate course requirements"
                || h == "graduate course requirements"
                || h == "program requirements"
                || h == "curriculum"
                || h == "program curriculum"
                || h == "curriculum requirements"
                || h.contains("required core")           // Graduate: "Required Core (33 credits)"
                || h.contains("additional requirements") // Graduate: "Additional Requirements (27 credits)"
                || h.contains("core requirements")       // Graduate: "Core Requirements"
                || h.contains("core courses")            // Certificate: "Core Courses (12 credits)"
                || h.contains("elective requirements")   // Graduate: "Elective Requirements"
                || h.contains("required courses")        // Graduate: "Required Courses"
                || h.hasPrefix("required ")              // Catch "Required ..." variations
        }

        func isRequirementsSectionStop(_ heading: String) -> Bool {
            let h = normalizedHeading(heading)
            return h == "curricular plan"
                || h == "learning outcomes"
                || h == "academic requirements"
                || h == "program honors"
                || h == "notes"
                || h == "additional links"
        }

        func normalizeRequirementCategoryLabel(_ raw: String) -> String {
            var s = raw.normalizedCatalogText()
            guard !s.isEmpty else { return s }

            // Many catalogs include trailing colons in headings (e.g., "Engineering Courses:").
            s = s.replacingOccurrences(of: "\\s*:+\\s*$", with: "", options: .regularExpression)

            // Normalize duplicate wording artifacts.
            s = s.replacingOccurrences(of: "(?i)\\bCourses\\s+Core\\s+Courses\\b", with: "Core Courses", options: .regularExpression)

            return s.normalizedCatalogText()
        }

        func buildDiagnostics(signature: String, usedMajorRequirementsSection: Bool, requirements: [DegreeRequirement]) -> ProgramRequirementsDiagnostics {
            let requiredCourseCount = requirements.reduce(0) { $0 + ($1.requiredCourses?.count ?? 0) }
            let selectCourseCount = requirements.reduce(0) { $0 + ($1.selectFrom?.count ?? 0) }
            let unique = Set(requirements.flatMap { ($0.requiredCourses ?? []) + ($0.selectFrom ?? []) })
            return ProgramRequirementsDiagnostics(
                signature: signature,
                usedMajorRequirementsSection: usedMajorRequirementsSection,
                categoriesFound: requirements.count,
                requiredCourseCount: requiredCourseCount,
                selectCourseCount: selectCourseCount,
                uniqueCourseCount: unique.count
            )
        }

        func parsedCreditsRequired(from category: String) -> Int {
            let s = category.normalizedCatalogText()
            guard let re = Self.cachedRegex("(?i)\\b(\\d+)\\s*credits?\\b") else { return 0 }
            let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
            guard let m = re.firstMatch(in: s, range: nsRange), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: s)
            else { return 0 }
            return Int(s[r]) ?? 0
        }

        func categoryLabel(for core: Element) -> String? {
            if let h = (try? core.select("h1,h2,h3,h4,h5,h6").first()),
               let t = try? h.text().normalizedCatalogText(), !t.isEmpty {
                return t
            }
            if let s = (try? core.select("strong,b").first()),
               let t = try? s.text().normalizedCatalogText(), !t.isEmpty, t.count <= 160 {
                return t
            }
            // Many Acalog layouts place the label immediately before the core block.
            var prev = try? core.previousElementSibling()
            var hops = 0
            while let p = prev, hops < 6 {
                let tag = p.tagName().lowercased()
                if tag == "script" || tag == "style" {
                    prev = try? p.previousElementSibling(); hops += 1
                    continue
                }
                let t = ((try? p.text()) ?? "").normalizedCatalogText()
                if !t.isEmpty, t.count <= 160 {
                    return t
                }
                prev = try? p.previousElementSibling(); hops += 1
            }
            return nil
        }

        // Prefer a section-scoped parse for Modern Campus/Acalog pages.
        // Many catalogs (including UB) structure program pages into ordered `div.acalog-core` blocks.
        // Scope parsing to the actual requirements section (e.g., "Course Requirements",
        // "Undergraduate Course Requirements", "Graduate Course Requirements"). This avoids
        // accidentally consuming non-requirement sections like "Admission Criteria".
        let requirementsCoreBlocks: [Element] = {
            guard let cores = try? doc.select("div.acalog-core"), cores.size() > 0 else { return [] }

            var blocks: [Element] = []
            blocks.reserveCapacity(cores.size())

            var capturing = false

            for i in 0..<cores.size() {
                let core = cores.get(i)

                // Check for section start/stop headings at any level (h2, h3, h4, etc.).
                // Graduate programs often use h3 for "Required Core", "Additional Requirements", etc.
                if let heading = (try? core.select("h1,h2,h3,h4,h5,h6").first()) {
                    let hText = (try? heading.text()) ?? ""
                    if capturing {
                        if isRequirementsSectionStop(hText) {
                            // Once we've reached Curricular Plan / Learning Outcomes, we're done.
                            break
                        }
                    } else {
                        if isRequirementsSectionStart(hText) {
                            capturing = true
                            // Skip the section header block itself; include the following blocks.
                            continue
                        }
                    }
                }

                if capturing {
                    blocks.append(core)
                }
            }

            return blocks
        }()

        let signature: String = {
            let hasAcalogCore = (try? doc.select("div.acalog-core").first()) != nil
            let hasAcalogCourse = (try? doc.select("li.acalog-course").first()) != nil
            let hasPreviewCourseLinks = (try? doc.select("a[href*=preview_course]").first()) != nil
            let hasPreviewCourseNoPopLinks = (try? doc.select("a[href*=preview_course_nopop]").first()) != nil
            let hasShowCourseOnClick = (try? doc.select("a[onClick*=showCourse],a[onclick*=showCourse]").first()) != nil

            let linkStyle: String = {
                if hasPreviewCourseLinks { return "preview_course" }
                if hasPreviewCourseNoPopLinks { return "preview_course_nopop" }
                if hasShowCourseOnClick { return "showCourse" }
                return "none"
            }()

            let usedScoped = !requirementsCoreBlocks.isEmpty
            return "acalogCore=\(hasAcalogCore ? 1 : 0);majorScoped=\(usedScoped ? 1 : 0);acalogCourse=\(hasAcalogCourse ? 1 : 0);link=\(linkStyle)"
        }()

        if !requirementsCoreBlocks.isEmpty {
            var out: [DegreeRequirement] = []
            out.reserveCapacity(requirementsCoreBlocks.count)

            func hasAnyCourses(_ r: DegreeRequirement) -> Bool {
                if let d = r.requiredCoursesDetailed, !d.isEmpty { return true }
                if let d = r.selectFromDetailed, !d.isEmpty { return true }
                if let c = r.requiredCourses, !c.isEmpty { return true }
                if let c = r.selectFrom, !c.isEmpty { return true }
                return false
            }

            func isContainerCategory(_ r: DegreeRequirement) -> Bool {
                // These are headings like "Cybersecurity Core (10-11 credits)" that often contain
                // only descriptive text and nested sub-headings (Focus Areas / Tracks).
                let hasDescription = !(r.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                return !hasAnyCourses(r) && (r.creditsRequired > 0 || hasDescription)
            }

            func isLikelySubsectionLabel(_ label: String) -> Bool {
                let s = label.normalizedCatalogText().lowercased()
                // UB commonly nests requirements under a "Core" heading via "Focus Area" blocks.
                if s.contains("focus area") { return true }
                // Other common subsection patterns.
                if s.contains("track") { return true }
                if s.contains("option") { return true }
                if s.contains("concentration") { return true }
                if s.contains("specialization") { return true }
                if s.contains("path") { return true }
                return false
            }

            func appendDetails(from r: DegreeRequirement, into out: inout [CourseDetail]) {
                // Preserve "OR" options early (common UB pattern: option line precedes other required courses).
                if let selectDetailed = r.selectFromDetailed, !selectDetailed.isEmpty {
                    out.append(contentsOf: selectDetailed)
                } else if let selectCodes = r.selectFrom, !selectCodes.isEmpty {
                    out.append(contentsOf: selectCodes.map { CourseDetail(code: $0) })
                }

                if let requiredDetailed = r.requiredCoursesDetailed, !requiredDetailed.isEmpty {
                    out.append(contentsOf: requiredDetailed)
                } else if let requiredCodes = r.requiredCourses, !requiredCodes.isEmpty {
                    out.append(contentsOf: requiredCodes.map { CourseDetail(code: $0) })
                }
            }

            func inferredSelectCount(from label: String) -> Int? {
                let s = label.normalizedCatalogText().lowercased()
                guard s.contains("elective") else { return nil }
                // Handle the common Modern Campus pattern: "One <X> Elective".
                if s.hasPrefix("one ") || s.contains(" one ") { return 1 }
                if s.hasPrefix("two ") || s.contains(" two ") { return 2 }
                if s.hasPrefix("three ") || s.contains(" three ") { return 3 }
                if s.hasPrefix("four ") || s.contains(" four ") { return 4 }
                if s.hasPrefix("five ") || s.contains(" five ") { return 5 }
                return nil
            }

            func isSequenceChoiceLabel(_ label: String) -> Bool {
                let s = label.normalizedCatalogText().lowercased()
                return s.contains("sequence from the following")
            }

            func isSingleChoiceFromFollowingLabel(_ label: String) -> Bool {
                let s = label.normalizedCatalogText().lowercased()
                guard s.contains("following") else { return false }
                // Exclude labels like "one course from each of the following areas".
                if s.contains("each of the following") { return false }

                let hasSingleChoiceSignal =
                    s.contains("one of the following") ||
                    s.contains("choose one") ||
                    s.contains("select one")
                return hasSingleChoiceSignal
            }

            func buildPredicateFromSequenceOptions(_ options: [[CourseDetail]]) -> RequirementPredicate? {
                guard !options.isEmpty else { return nil }
                let branches = options.compactMap { option -> RequirementPredicate? in
                    let unique = Array(Set(option)).sorted { $0.code < $1.code }
                    guard !unique.isEmpty else { return nil }
                    if unique.count == 1 {
                        return .course(unique[0])
                    }
                    return .all(unique.map { RequirementPredicate.course($0) })
                }
                guard !branches.isEmpty else { return nil }
                return .any(branches, selectCount: 1)
            }

            for core in requirementsCoreBlocks {
                let label = normalizeRequirementCategoryLabel(categoryLabel(for: core) ?? "Requirements")
                guard !label.isEmpty else { continue }

                func hasNestedCoreAncestor(_ el: Element) -> Bool {
                    var parent = el.parent()
                    while let p = parent {
                        if p.tagName().lowercased() == "div", p.hasClass("acalog-core") {
                            // If we hit the current core, there is no nested core ancestor.
                            if p === core { return false }
                            // Any other .acalog-core ancestor indicates this element belongs to a nested block.
                            return true
                        }
                        parent = p.parent()
                    }
                    return false
                }
                
                // Filter out non-requirement categories
                let labelLower = label.lowercased()
                let skipPatterns = [
                    "notes", "note:", "footnote",
                    "^or$", "^and$", "^then$",
                    "fall semester", "spring semester", "summer semester",
                    "admission criteria", "admission requirements", "application requirements",
                    "total credits",
                    "program honors", "program distinction", "curricular plan",
                    "learning outcomes",
                    "disrtibuted as follows", "distributed as follows", "acceptable substitutes"
                ]
                
                let shouldSkip = skipPatterns.contains { pattern in
                    if pattern.hasPrefix("^") {
                        // Regex pattern
                        return labelLower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                    } else {
                        // Simple contains
                        return labelLower.contains(pattern)
                    }
                }
                
                if shouldSkip {
                    continue
                }

                var requiredCoursesDetailed: [CourseDetail] = []
                requiredCoursesDetailed.reserveCapacity(32)

                var selectGroupsDetailed: [[CourseDetail]] = []
                selectGroupsDetailed.reserveCapacity(8)

                var sequenceOptionGroupsDetailed: [[CourseDetail]] = []
                sequenceOptionGroupsDetailed.reserveCapacity(4)

                var currentDescription: String? = nil
                var currentSelectCount: Int? = nil

                func applyRuleSignals(from text: String) {
                    let t = text.normalizedCatalogText()
                    guard !t.isEmpty else { return }

                    if t.range(of: "\\bselect\\b|\\bchoose\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                        currentDescription = currentDescription ?? t
                        if let re = Self.cachedRegex("(?i)\\b(?:select|choose)\\s+(\\d+)\\b") {
                            let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
                            if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 2,
                               let r = Range(m.range(at: 1), in: t) {
                                currentSelectCount = Int(t[r])
                            }
                        }
                    }
                }

                func addDetailsFromLine(_ t: String) {
                    let normalized = t.normalizedCatalogText()
                    guard !normalized.isEmpty else { return }

                    applyRuleSignals(from: normalized)

                    let details = Self.extractCourseDetails(from: normalized)
                    guard !details.isEmpty else { return }

                    // Inline OR is common: "CSE 115 OR MGS 314".
                    // If we see OR and multiple course codes in the same line, treat it as a select group.
                    if normalized.range(of: "\\bor\\b", options: [.regularExpression, .caseInsensitive]) != nil, details.count >= 2 {
                        selectGroupsDetailed.append(details)
                    } else {
                        requiredCoursesDetailed.append(contentsOf: details)
                    }
                }

                // Notes/select rules within the block
                if let adhoc = try? core.select(".acalog-adhoc") {
                    for a in adhoc {
                        if hasNestedCoreAncestor(a) { continue }
                        let t = ((try? a.text()) ?? "").normalizedCatalogText()
                        if t.range(of: "\\bselect\\b|\\bchoose\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                            currentDescription = t
                            if let re = Self.cachedRegex("(?i)\\b(?:select|choose)\\s+(\\d+)\\b") {
                                let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
                                if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 2,
                                   let r = Range(m.range(at: 1), in: t) {
                                    currentSelectCount = Int(t[r])
                                }
                            }
                        }
                    }
                }

                // Primary extraction: list items / course rows preserve grouping context.
                if let items = try? core.select("li"), items.size() > 0 {
                    func hasListItemAncestor(_ el: Element) -> Bool {
                        var parent = el.parent()
                        while let p = parent {
                            if p.tagName().lowercased() == "li" { return true }
                            parent = p.parent()
                        }
                        return false
                    }

                    // First pass: collect (text, isAdhoc) in document order,
                    // filtering out already-excluded items.
                    var liEntries: [(text: String, isAdhoc: Bool)] = []
                    for li in items {
                        if hasNestedCoreAncestor(li) { continue }
                        if hasListItemAncestor(li) { continue }

                        var parts: [String] = []
                        let own = li.ownText()
                        let ot = own.normalizedCatalogText()
                        if !ot.isEmpty { parts.append(ot) }
                        if let directLinks = try? li.select("> a, > span > a") {
                            for a in directLinks {
                                let at = ((try? a.text()) ?? "").normalizedCatalogText()
                                if !at.isEmpty { parts.append(at) }
                            }
                        }

                        let t = parts.joined(separator: " ").normalizedCatalogText()
                        if t.isEmpty { continue }
                        liEntries.append((text: t, isAdhoc: li.hasClass("acalog-adhoc")))
                    }

                    // Second pass: detect multi-line OR groups.
                    // A standalone "or"/"Or"/"OR" separator between course-bearing lines
                    // means both neighbours should be a selectFrom group.
                    //
                    // We scan for contiguous runs separated by "or" tokens, then:
                    //   – If the run has ≥2 members each containing course codes → selectFrom group.
                    //   – Otherwise fall back to treating each line individually.
                    var groups: [[String]] = []      // each group is one selectFrom batch
                    var currentGroup: [String] = []
                    var inOrChain = false

                    for (idx, entry) in liEntries.enumerated() {
                        if entry.isAdhoc {
                            // Flush any open OR chain first
                            if inOrChain && currentGroup.count >= 2 {
                                groups.append(currentGroup)
                            } else {
                                for item in currentGroup { applyRuleSignals(from: item) }
                            }
                            currentGroup = []
                            inOrChain = false
                            applyRuleSignals(from: entry.text)
                            continue
                        }

                        let lower = entry.text.trimmingCharacters(in: .whitespaces).lowercased()

                        // Standalone "or" separator
                        if lower == "or" {
                            inOrChain = true
                            continue
                        }

                        if inOrChain {
                            // We're inside an OR chain — accumulate
                            currentGroup.append(entry.text)
                        } else {
                            // Flush previous non-OR group (single item) and start fresh
                            if !currentGroup.isEmpty {
                                for item in currentGroup { addDetailsFromLine(item) }
                                currentGroup = []
                            }
                            currentGroup = [entry.text]
                        }

                        // Look ahead: if the NEXT entry is NOT "or", close the chain
                        let nextIdx = idx + 1
                        let nextIsOr: Bool
                        if nextIdx < liEntries.count {
                            let nextLower = liEntries[nextIdx].text.trimmingCharacters(in: .whitespaces).lowercased()
                            nextIsOr = (nextLower == "or")
                        } else {
                            nextIsOr = false
                        }

                        if inOrChain && !nextIsOr {
                            // End of OR chain
                            if currentGroup.count >= 2 {
                                groups.append(currentGroup)
                            } else {
                                for item in currentGroup { addDetailsFromLine(item) }
                            }
                            currentGroup = []
                            inOrChain = false
                        }
                    }

                    // Flush any remaining items
                    if inOrChain && currentGroup.count >= 2 {
                        groups.append(currentGroup)
                    } else {
                        for item in currentGroup { addDetailsFromLine(item) }
                    }

                    // Emit detected multi-line OR groups as selectFrom batches
                    for group in groups {
                        var groupDetails: [CourseDetail] = []
                        for line in group {
                            groupDetails.append(contentsOf: Self.extractCourseDetails(from: line))
                        }
                        if !groupDetails.isEmpty {
                            selectGroupsDetailed.append(groupDetails)
                        }
                    }

                    // Detect grouped AND-sequences for labels like "One sequence from the following".
                    // Example:
                    //   MTH 121 ... AND
                    //   MTH 122 ...
                    //   MTH 141 ... AND
                    //   MTH 142 ...
                    if isSequenceChoiceLabel(label) || isSingleChoiceFromFollowingLabel(label) {
                        var currentOption: [CourseDetail] = []

                        for entry in liEntries where !entry.isAdhoc {
                            let text = entry.text.normalizedCatalogText()
                            guard !text.isEmpty else { continue }

                            let details = Self.extractCourseDetails(from: text)
                            guard !details.isEmpty else { continue }

                            currentOption.append(contentsOf: details)

                            let endsWithAnd = text.range(of: "\\band\\s*$", options: [.regularExpression, .caseInsensitive]) != nil
                            if !endsWithAnd {
                                let unique = Array(Set(currentOption)).sorted { $0.code < $1.code }
                                if !unique.isEmpty {
                                    sequenceOptionGroupsDetailed.append(unique)
                                }
                                currentOption = []
                            }
                        }

                        if !currentOption.isEmpty {
                            let unique = Array(Set(currentOption)).sorted { $0.code < $1.code }
                            if !unique.isEmpty {
                                sequenceOptionGroupsDetailed.append(unique)
                            }
                        }
                    }
                }

                if requiredCoursesDetailed.isEmpty, selectGroupsDetailed.isEmpty {
                    // Some programs provide only prose requirements (no explicit course links/codes).
                    // Preserve a bounded description so the category is still represented.
                    let prose = ((try? core.select("p, li, div").text()) ?? "").normalizedCatalogText()
                    if !prose.isEmpty {
                        let bounded = String(prose.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !bounded.isEmpty {
                            currentDescription = currentDescription ?? bounded
                        }
                    }
                }

                if let rows = try? core.select(".acalog-course") {
                    for r in rows {
                        if hasNestedCoreAncestor(r) { continue }
                        let t = ((try? r.text()) ?? "").normalizedCatalogText()
                        if t.isEmpty { continue }
                        addDetailsFromLine(t)
                    }
                }

                let requiredUniqueDetailed = Array(Set(requiredCoursesDetailed)).sorted { $0.code < $1.code }
                var selectGroupsUnique: [[CourseDetail]] = selectGroupsDetailed.map { group in
                    Array(Set(group)).sorted { $0.code < $1.code }
                }
                selectGroupsUnique.removeAll(where: { $0.isEmpty })

                // Elective blocks often have no explicit OR tokens. Use category label to infer selectCount.
                let inferred = inferredSelectCount(from: label)
                let selectCount = currentSelectCount ?? inferred
                let sequenceChoicePredicate = buildPredicateFromSequenceOptions(sequenceOptionGroupsDetailed)

                let credits = parsedCreditsRequired(from: label)

                // If the label implies electives and we have requiredUniqueDetailed but no explicit OR groups,
                // treat the whole set as select-from.
                if selectGroupsUnique.isEmpty, inferred != nil, !requiredUniqueDetailed.isEmpty {
                    let codes = requiredUniqueDetailed.map { $0.code }
                    let req = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: label,
                        requiredCourses: nil,
                        requiredCoursesDetailed: nil,
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: codes,
                        selectFromDetailed: requiredUniqueDetailed,
                        selectCount: (selectCount ?? 1),
                        requirementPredicate: sequenceChoicePredicate
                    )
                    out.append(req)
                    logger.scraper("🧩 Requirements category=\(label) courses=\(codes.count) mode=select")
                    continue
                }

                // Emit required row (AND semantics)
                if !requiredUniqueDetailed.isEmpty {
                    let codes = requiredUniqueDetailed.map { $0.code }
                    let req = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: label,
                        requiredCourses: codes,
                        requiredCoursesDetailed: requiredUniqueDetailed,
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: nil,
                        selectFromDetailed: nil,
                        selectCount: nil,
                        requirementPredicate: sequenceChoicePredicate
                    )
                    out.append(req)
                } else if credits > 0 || !(currentDescription?.isEmpty ?? true) {
                    // Create empty category if it has credit requirements or a description
                    // This allows users to manually add courses to empty categories
                    let req = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: label,
                        requiredCourses: [],
                        requiredCoursesDetailed: [],
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: nil,
                        selectFromDetailed: nil,
                        selectCount: nil,
                        requirementPredicate: sequenceChoicePredicate
                    )
                    out.append(req)
                    logger.scraper("📝 Empty category preserved: \(label) (\(credits) credits)")
                }

                // Emit select-from rows (OR semantics)
                for group in selectGroupsUnique {
                    let codes = group.map { $0.code }
                    let req = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: label,
                        requiredCourses: nil,
                        requiredCoursesDetailed: nil,
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: codes,
                        selectFromDetailed: group,
                        selectCount: (selectCount ?? 1),
                        requirementPredicate: sequenceChoicePredicate
                    )
                    out.append(req)
                }

                if requiredUniqueDetailed.isEmpty, selectGroupsUnique.isEmpty {
                    continue
                }
            }

            // Post-process: Some catalogs (notably UB) use an empty "Core (... credits)" heading
            // followed by nested subsection blocks ("Technical Focus Area", "Managerial Focus Area", etc.).
            // We merge those subsections into the Core section so the UI matches the source layout
            // and does not show an empty "No requirements found." table.
            func mergeNestedSubsectionsIntoCore(_ input: [DegreeRequirement]) -> [DegreeRequirement] {
                guard input.count >= 2 else { return input }

                var merged: [DegreeRequirement] = []
                merged.reserveCapacity(input.count)

                var i = 0
                while i < input.count {
                    let current = input[i]

                    // Only consider merging for "Core" container headings.
                    let currentLabelLower = current.category.normalizedCatalogText().lowercased()
                    let isCoreContainer = isContainerCategory(current) && currentLabelLower.contains("core")

                    guard isCoreContainer else {
                        merged.append(current)
                        i += 1
                        continue
                    }

                    var j = i + 1
                    var stitched: [CourseDetail] = []
                    var sawChild = false
                    var lastChildLabel: String? = nil

                    while j < input.count {
                        let child = input[j]
                        let childLabel = child.category.normalizedCatalogText()

                        // Only merge *explicit* subsections (Focus Area / Track / Option / Concentration...).
                        // This ensures independent sections like "Three Electives (9-12 credits)" remain their
                        // own sections across all minors/majors (i.e. no hardcoding to Cybersecurity).
                        if isLikelySubsectionLabel(childLabel) {
                            if lastChildLabel != childLabel {
                                stitched.append(CourseDetail(code: "", title: childLabel, credits: nil))
                                lastChildLabel = childLabel
                            }
                            appendDetails(from: child, into: &stitched)
                            sawChild = true
                            j += 1
                            continue
                        }

                        // Stop as soon as we leave the subsection block(s).
                        break
                    }

                    if sawChild, !stitched.isEmpty {
                        let req = DegreeRequirement(
                            id: current.id,
                            degreeType: current.degreeType,
                            major: current.major,
                            category: current.category,
                            requiredCourses: nil,
                            requiredCoursesDetailed: stitched,
                            creditsRequired: current.creditsRequired,
                            description: current.description,
                            selectFrom: nil,
                            selectFromDetailed: nil,
                            selectCount: nil
                        )
                        merged.append(req)
                        i = j
                        continue
                    }

                    merged.append(current)
                    i += 1
                }

                return merged
            }

            out = mergeNestedSubsectionsIntoCore(out)

            logger.scraper("✅ Requirements parse complete. rows=\(out.count)")
            let diagnostics = buildDiagnostics(signature: signature, usedMajorRequirementsSection: true, requirements: out)
            return (requirements: out, diagnostics: diagnostics)
        }

        // Use Acalog's `acalog-core` blocks if present; otherwise, fall back to the main content.
        let containers: Elements = {
            if let core = try? doc.select("div.acalog-core"), core.size() > 0 {
                return core
            }
            if let main = try? doc.select("#acalog-content, #gateway-page-content, #content"), main.size() > 0 {
                return main
            }
            return (try? doc.getAllElements()) ?? Elements()
        }()

        var results: [DegreeRequirement] = []

        for container in containers {
            // Walk all descendants in document order to associate headings with following lists.
            let all = (try? container.getAllElements()) ?? Elements()

            // Many UB (Modern Campus/Acalog) program pages include:
            // - non-requirement sections like "Admission Criteria" and "Curricular Plan"
            // - term/semester subheadings under Curricular Plan (e.g., "Fifth Year Fall")
            //
            // We only want the actual requirements section(s) and should stop when we reach
            // Curricular Plan / Learning Outcomes, etc.
            var inRequirementsSection = false

            var currentCategory: String?
            var requiredCoursesDetailed: [CourseDetail] = []
            var selectGroupsDetailed: [[CourseDetail]] = []
            var currentDescription: String? = nil
            var currentSelectCount: Int? = nil

            func flushCategoryIfNeeded() {
                let cat = normalizeRequirementCategoryLabel(currentCategory ?? "")
                guard !cat.isEmpty else {
                    requiredCoursesDetailed.removeAll(keepingCapacity: true)
                    selectGroupsDetailed.removeAll(keepingCapacity: true)
                    currentDescription = nil
                    currentSelectCount = nil
                    return
                }

                let requiredUniqueDetailed = Array(Set(requiredCoursesDetailed)).sorted { $0.code < $1.code }
                var selectGroupsUnique: [[CourseDetail]] = selectGroupsDetailed.map { group in
                    Array(Set(group)).sorted { $0.code < $1.code }
                }
                selectGroupsUnique.removeAll(where: { $0.isEmpty })

                guard !requiredUniqueDetailed.isEmpty || !selectGroupsUnique.isEmpty else {
                    requiredCoursesDetailed.removeAll(keepingCapacity: true)
                    selectGroupsDetailed.removeAll(keepingCapacity: true)
                    currentDescription = nil
                    currentSelectCount = nil
                    return
                }
                
                // Filter out non-requirement categories in fallback parser
                let catLower = cat.lowercased()
                let skipPatterns = [
                    "notes", "note:", "footnote",
                    "^or$", "^and$", "^then$",
                    "fall semester", "spring semester", "summer semester",
                    "first year", "second year", "third year", "fourth year", "year 1", "year 2", "year 3", "year 4",
                    "admission criteria", "admission requirements", "application requirements",
                    "total credits",
                    "program honors", "program distinction", "curricular plan",
                    "learning outcomes",
                    "disrtibuted as follows", "distributed as follows", "acceptable substitutes"
                ]
                
                let shouldSkip = skipPatterns.contains { pattern in
                    if pattern.hasPrefix("^") {
                        return catLower.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                    } else {
                        return catLower.contains(pattern)
                    }
                }
                
                if shouldSkip {
                    requiredCoursesDetailed.removeAll(keepingCapacity: true)
                    selectGroupsDetailed.removeAll(keepingCapacity: true)
                    currentDescription = nil
                    currentSelectCount = nil
                    return
                }

                let credits = parsedCreditsRequired(from: cat)

                if !requiredUniqueDetailed.isEmpty {
                    let codes = requiredUniqueDetailed.map { $0.code }
                    let requirement = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: cat,
                        requiredCourses: codes,
                        requiredCoursesDetailed: requiredUniqueDetailed,
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: nil,
                        selectFromDetailed: nil,
                        selectCount: nil
                    )
                    results.append(requirement)
                }

                for group in selectGroupsUnique {
                    let codes = group.map { $0.code }
                    let requirement = DegreeRequirement(
                        degreeType: "Unknown",
                        major: "Unknown",
                        category: cat,
                        requiredCourses: nil,
                        requiredCoursesDetailed: nil,
                        creditsRequired: credits,
                        description: currentDescription,
                        selectFrom: codes,
                        selectFromDetailed: group,
                        selectCount: (currentSelectCount ?? 1)
                    )
                    results.append(requirement)
                }

                logger.scraper("🧩 Requirements category=\(cat) rows=\((requiredUniqueDetailed.isEmpty ? 0 : 1) + selectGroupsUnique.count)")

                requiredCoursesDetailed.removeAll(keepingCapacity: true)
                selectGroupsDetailed.removeAll(keepingCapacity: true)
                currentDescription = nil
                currentSelectCount = nil
            }

            for el in all {
                let tag = el.tagName()

                // Heading = start of a new category
                if tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" {
                    let rawHeading = (try? el.text()) ?? ""
                    let headNorm = normalizedHeading(rawHeading)

                    // Stop parsing once we've reached non-requirement sections that follow requirements.
                    // Accept h2, h3, or h4 for stop sections (graduate programs often use h3)
                    if inRequirementsSection, (tag == "h2" || tag == "h3" || tag == "h4"), isRequirementsSectionStop(headNorm) {
                        if currentCategory != nil {
                            flushCategoryIfNeeded()
                        }
                        break
                    }

                    // Accept h2, h3, or h4 for start sections (graduate programs often use h3)
                    // Don’t start parsing until we hit a requirements section.
                    if !inRequirementsSection {
                        if (tag == "h2" || tag == "h3" || tag == "h4"), isRequirementsSectionStart(headNorm) {
                            inRequirementsSection = true
                        } else {
                            continue
                        }
                    }

                    // flush previous
                    if currentCategory != nil {
                        flushCategoryIfNeeded()
                    }
                    currentCategory = normalizeRequirementCategoryLabel(rawHeading)
                    continue
                }

                // Many Acalog pages use a bold/strong line instead of an h2/h3.
                if tag == "strong" {
                    guard inRequirementsSection else { continue }
                    let t = ((try? el.text()) ?? "").normalizedCatalogText()
                    if !t.isEmpty, t.count <= 80 {
                        if currentCategory != nil {
                            flushCategoryIfNeeded()
                        }
                        currentCategory = normalizeRequirementCategoryLabel(t)
                        continue
                    }
                }

                // Course links are often the most reliable signal.
                if tag == "a" {
                    guard inRequirementsSection else { continue }
                    let href = (try? el.attr("href")) ?? ""
                    if href.localizedCaseInsensitiveContains("preview_course") {
                        let t = (try? el.text()) ?? ""
                        let details = Self.extractCourseDetails(from: t)
                        if !details.isEmpty {
                            requiredCoursesDetailed.append(contentsOf: details)
                        }
                        continue
                    }
                }

                // Plain list items often contain course codes without links.
                if tag == "li", !el.hasClass("acalog-adhoc") {
                    guard inRequirementsSection else { continue }
                    let t = ((try? el.text()) ?? "").normalizedCatalogText()
                    if t.range(of: "\\bselect\\b|\\bchoose\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                        currentDescription = currentDescription ?? t
                        if let re = Self.cachedRegex("(?i)\\b(?:select|choose)\\s+(\\d+)\\b") {
                            let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
                            if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 2,
                               let r = Range(m.range(at: 1), in: t) {
                                currentSelectCount = Int(t[r])
                            }
                        }
                    }
                    let details = Self.extractCourseDetails(from: t)
                    if !details.isEmpty {
                        if t.range(of: "\\bor\\b", options: [.regularExpression, .caseInsensitive]) != nil, details.count >= 2 {
                            selectGroupsDetailed.append(details)
                        } else {
                            requiredCoursesDetailed.append(contentsOf: details)
                        }
                    }
                    continue
                }

                if tag == "p" {
                    guard inRequirementsSection else { continue }
                    let t = ((try? el.text()) ?? "").normalizedCatalogText()
                    guard !t.isEmpty else { continue }

                    if t.range(of: "\\bselect\\b|\\bchoose\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                        currentDescription = currentDescription ?? t
                        if let re = Self.cachedRegex("(?i)\\b(?:select|choose)\\s+(\\d+)\\b") {
                            let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
                            if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 2,
                               let r = Range(m.range(at: 1), in: t) {
                                currentSelectCount = Int(t[r])
                            }
                        }
                    }

                    let details = Self.extractCourseDetails(from: t)
                    if !details.isEmpty {
                        if t.range(of: "\\bor\\b", options: [.regularExpression, .caseInsensitive]) != nil, details.count >= 2 {
                            selectGroupsDetailed.append(details)
                        } else {
                            requiredCoursesDetailed.append(contentsOf: details)
                        }
                    } else if currentDescription == nil {
                        // Prose-only requirement sections (common in professional catalogs).
                        currentDescription = String(t.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    continue
                }

                // Course rows
                if el.hasClass("acalog-course") {
                    guard inRequirementsSection else { continue }
                    let text = (try? el.text()) ?? ""
                    let details = Self.extractCourseDetails(from: text)
                    if !details.isEmpty {
                        let t = text.normalizedCatalogText()
                        if t.range(of: "\\bor\\b", options: [.regularExpression, .caseInsensitive]) != nil, details.count >= 2 {
                            selectGroupsDetailed.append(details)
                        } else {
                            requiredCoursesDetailed.append(contentsOf: details)
                        }
                    }
                    continue
                }

                // Adhoc rows (OR/notes)
                if el.hasClass("acalog-adhoc") {
                    guard inRequirementsSection else { continue }
                    let t = ((try? el.text()) ?? "").normalizedCatalogText()
                    if t.range(of: "\\bselect\\b|\\bchoose\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                        currentDescription = t

                        if let re = Self.cachedRegex("(?i)\\b(?:select|choose)\\s+(\\d+)\\b") {
                            let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
                            if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 2,
                               let r = Range(m.range(at: 1), in: t) {
                                currentSelectCount = Int(t[r])
                            }
                        }
                    }
                    continue
                }
            }

            // flush last category in this container
            if currentCategory != nil {
                flushCategoryIfNeeded()
            }
        }

        logger.scraper("✅ Requirements parse complete. rows=\(results.count)")
        let diagnostics = buildDiagnostics(signature: signature, usedMajorRequirementsSection: false, requirements: results)
        return (requirements: results, diagnostics: diagnostics)
    }

    nonisolated private static func extractCourseCodes(from text: String) -> [String] {
        let details = extractCourseDetails(from: text)
        return details.map { $0.code }
    }
    
    /// Extract detailed course information including code, title, and credits
    /// Formats: "CSE 113 - Foundations of Computer Science I (3)"
    ///          "MTH 131LR Calculus I - 4 credits"
    ///          "BIO 201 Introduction to Biology 3 cr"
    nonisolated private static func extractCourseDetails(from text: String) -> [CourseDetail] {
        let s = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "(?i)\\bview\\s+course\\s+details\\s+for\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^[•\\-\\s]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !s.isEmpty else { return [] }

        // Pattern to match: SUBJ NUM [optional suffix] [separator] [title] [credits]
        // Examples:
        // - "CSE 113 - Foundations of Computer Science I (3 credits)"
        // - "MTH 131LR Calculus I 4 cr"
        // - "ECO 181 Intro to Macroeconomics - 3"
        guard let codeRe = Self.cachedRegex("(?i)\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})([A-Z]{0,6})\\b") else {
            return []
        }

        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = codeRe.matches(in: s, range: range)
        guard !matches.isEmpty else { return [] }

        var results: [CourseDetail] = []
        var seen = Set<String>()

        // Heuristics to prevent parsing natural-language prose as course codes.
        // We intentionally keep these conservative and validate using the derived title/credits.
        let stopwordSubjects: Set<String> = [
            "A", "AN", "THE",
            "OF", "TO", "IN", "ON", "AT", "BY", "AS", "FOR", "FROM", "WITH", "VIA", "PER",
            "AND", "OR",
            // Avoid false positives from natural-language ranges like "Any 300/400 level".
            "ANY", "ALL",
            // Numbers spelled out sometimes get captured by the regex.
            "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN",
            // Credit/total prose that can appear in requirement text.
            "CREDIT", "CREDITS", "HOUR", "HOURS", "TOTAL", "LEVEL"
        ]

        for m in matches {
            guard m.numberOfRanges >= 3,
                  let r1 = Range(m.range(at: 1), in: s),
                  let r2 = Range(m.range(at: 2), in: s)
            else { continue }

            // Even though the regex is case-insensitive, real catalog course codes are
            // overwhelmingly written with an ALL-CAPS subject. This prevents false
            // positives like "the 120 credit hour total".
            let rawSubj = String(s[r1])
            guard rawSubj == rawSubj.uppercased() else { continue }

            let subj = rawSubj.uppercased()
            let num = String(s[r2]).uppercased()
            let suffix: String = {
                guard m.numberOfRanges >= 4, let r3 = Range(m.range(at: 3), in: s) else { return "" }
                return String(s[r3]).uppercased()
            }()

            // Avoid placeholder ranges like "MTH 49X courses".
            if suffix.range(of: "^X+$", options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            let code = "\(subj) \(num)"
            
            // Additional validation: subject code should be 2-6 letters, all uppercase
            guard subj.count >= 2 && subj.count <= 6 else { continue }
            guard subj.allSatisfy({ $0.isLetter && $0.isUppercase }) else { continue }
            
            // Course number should be 2-4 digits (no text like "hour", "credit", etc.)
            guard num.count >= 2 && num.count <= 4 && num.allSatisfy({ $0.isNumber }) else { continue }
            
            guard seen.insert(code).inserted else { continue }
            
            // Extract title and credits from the text after the code
            let matchEnd = m.range.upperBound
            guard matchEnd < s.count else {
                results.append(CourseDetail(code: code))
                continue
            }
            
            let afterCode = String(s[s.index(s.startIndex, offsetBy: matchEnd)...])
            var (title, credits) = parseTitleAndCredits(from: afterCode)

            // Sanity check: credits like 120/125 are almost certainly prose ("120 credit hour total").
            if let c = credits,
               let v = Double(c.trimmingCharacters(in: .whitespacesAndNewlines)),
               v > 30 {
                credits = nil
            }

            // If the derived title is clearly describing total-program credits rather than a course,
            // drop it. This specifically prevents rows like "THE 120 credit hour total".
            if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                let tl = t.lowercased()
                if tl.contains("credit hour") || tl.contains("credit hours") || tl.contains("hour total") || tl.contains("credit total") || tl.contains("total credits") {
                    continue
                }
            }

            // Stopword-like subjects (e.g., THE/AND/OF) should only pass if they look like a real
            // course listing (title exists and starts with an uppercase letter).
            if stopwordSubjects.contains(subj) {
                guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let first = t.first,
                      first.isUppercase
                else {
                    continue
                }
            }

            // If we couldn't derive either a title or credits, it's usually a range/explanatory fragment
            // (e.g., "MTH 300/400-level courses" or "Calculus 1 (MTH 141 or MTH 153)").
            if title == nil, credits == nil {
                continue
            }

            results.append(CourseDetail(code: code, title: title, credits: credits))
        }

        return results
    }
    
    /// Instance method wrapper that enhances course details with catalog cache
    private func extractCourseDetailsWithCatalogFallback(from text: String) async -> [CourseDetail] {
        var results = Self.extractCourseDetails(from: text)
        
        // Enhance results with course catalog data (fallback for missing titles/credits)
        for i in 0..<results.count {
            let course = results[i]
            
            // If title or credits are missing, check the course catalog cache
            if course.title == nil || course.credits == nil {
                if let catalogCourse = courseDetailsByCode[course.code] {
                    results[i] = CourseDetail(
                        code: course.code,
                        title: course.title ?? catalogCourse.title,
                        credits: course.credits ?? catalogCourse.credits
                    )
                }
            }
        }
        
        return results
    }
    
    /// Enhance degree requirements by filling in missing course titles/credits from catalog cache
    private func enhanceRequirementsWithCatalogData(_ requirements: [DegreeRequirement]) -> [DegreeRequirement] {
        let logger = DebugLogger.shared
        var enhancedCount = 0
        var missingCount = 0
        
        let result = requirements.map { req in
            // Enhance requiredCoursesDetailed
            let enhancedRequired = req.requiredCoursesDetailed?.map { course in
                if course.title == nil || course.credits == nil {
                    if let catalogCourse = courseDetailsByCode[course.code] {
                        enhancedCount += 1
                        if enhancedCount <= 5 {
                            let addedTitle = course.title == nil ? "title" : ""
                            let addedCredits = course.credits == nil ? "credits" : ""
                            let sep = !addedTitle.isEmpty && !addedCredits.isEmpty ? ", " : ""
                            let creditsValue = catalogCourse.credits ?? "?"
                            logger.log("   ✨ Enhanced \(course.code): added \(addedTitle)\(sep)\(addedCredits) (\(creditsValue))")
                        }
                        return CourseDetail(
                            code: course.code,
                            title: course.title ?? catalogCourse.title,
                            credits: course.credits ?? catalogCourse.credits
                        )
                    } else {
                        missingCount += 1
                    }
                }
                return course
            }
            
            // Enhance selectFromDetailed
            let enhancedSelect = req.selectFromDetailed?.map { course in
                if course.title == nil || course.credits == nil {
                    if let catalogCourse = courseDetailsByCode[course.code] {
                        enhancedCount += 1
                        if enhancedCount <= 5 {
                            let addedTitle = course.title == nil ? "title" : ""
                            let addedCredits = course.credits == nil ? "credits" : ""
                            let sep = !addedTitle.isEmpty && !addedCredits.isEmpty ? ", " : ""
                            let creditsValue = catalogCourse.credits ?? "?"
                            logger.log("   ✨ Enhanced \(course.code): added \(addedTitle)\(sep)\(addedCredits) (\(creditsValue))")
                        }
                        return CourseDetail(
                            code: course.code,
                            title: course.title ?? catalogCourse.title,
                            credits: course.credits ?? catalogCourse.credits
                        )
                    } else {
                        missingCount += 1
                    }
                }
                return course
            }
            
            // Return enhanced requirement
            return DegreeRequirement(
                id: req.id,
                degreeType: req.degreeType,
                major: req.major,
                category: req.category,
                requiredCourses: req.requiredCourses,
                requiredCoursesDetailed: enhancedRequired,
                creditsRequired: req.creditsRequired,
                description: req.description,
                selectFrom: req.selectFrom,
                selectFromDetailed: enhancedSelect,
                selectCount: req.selectCount
            )
        }
        
        if enhancedCount > 0 || missingCount > 0 {
            logger.log("📊 Course enhancement: \(enhancedCount) courses enhanced, \(missingCount) still missing data (not in catalog cache)")
        }
        
        return result
    }
    
    /// Parse title and credits from text after course code
    /// Input: " - Foundations of Computer Science I (3 credits)" or " Calculus I 4 cr"
    /// Output: (title: "Foundations of Computer Science I", credits: "3")
    nonisolated private static func parseTitleAndCredits(from text: String) -> (title: String?, credits: String?) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading separators: "-", "–", ":", etc.
        s = s.replacingOccurrences(of: "^[\\s\\-–:]+", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !s.isEmpty else { return (nil, nil) }

        // If the title starts with list punctuation, it's almost certainly not a real title.
        if s.hasPrefix(",") || s.hasPrefix(")") || s.hasPrefix(";") || s.hasPrefix("/") {
            return (nil, nil)
        }

        // If the text after the code is clearly just a logical connector or the start of
        // another course code, do NOT treat it as a title.
        let upper = s.uppercased()
        if upper == "OR" || upper == "AND" { return (nil, nil) }
        if upper.hasPrefix("OR ") || upper.hasPrefix("AND ") { return (nil, nil) }
        if s.range(of: "^(?i)(?:OR|AND)\\b", options: .regularExpression) != nil {
            return (nil, nil)
        }
        if s.range(of: "^(?i)\\b[A-Z]{2,6}\\s*[-–]?\\s*\\d{2,4}[A-Z]{0,6}\\b", options: .regularExpression) != nil {
            return (nil, nil)
        }

        // If the remaining text contains another course code, we're probably parsing a multi-course
        // requirement line like "MTH 411, STA 301 ...; OR". Don't treat the remainder as a title.
        if s.range(of: "(?i)\\b[A-Z]{2,6}\\s*[-–]?\\s*\\d{2,4}[A-Z]{0,6}\\b", options: .regularExpression) != nil {
            return (nil, nil)
        }
        
        // Extract credits: look for patterns like "(3)", "3 credits", "4 cr", "3-4 credits", "1-6 credits", "Credits: 3".
        // Also handle fractional credits like ".5"/"0.5".
        var credits: String? = nil
        func normalizeCreditsValue(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{2013}", with: "-")
                .replacingOccurrences(of: "\u{2014}", with: "-")
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            if trimmed.hasPrefix(".") { return "0" + trimmed }
            return trimmed
        }

        func creditsString(from match: NSTextCheckingResult, in text: String) -> String? {
            guard match.numberOfRanges >= 2, let r1 = Range(match.range(at: 1), in: text) else { return nil }
            let first = normalizeCreditsValue(String(text[r1]))
            if match.numberOfRanges >= 3, let r2 = Range(match.range(at: 2), in: text) {
                let second = normalizeCreditsValue(String(text[r2]))
                return "\(first)-\(second)"
            }
            return first
        }

        let creditPatterns = [
            "\\(\\s*(\\d+(?:\\.\\d+)?|\\.\\d+)\\s*(?:[-–]\\s*(\\d+(?:\\.\\d+)?|\\.\\d+)\\s*)?(?:credits?|crs?|hrs?)?\\s*\\)",
            "(?:credits?|crs?|hrs?)\\s*/\\s*(?:units?)\\s*:?\\s*(\\d+(?:\\.\\d+)?|\\.\\d+)(?:\\s*[-–]\\s*(\\d+(?:\\.\\d+)?|\\.\\d+))?",
            "(?:credits?|crs?|hrs?)\\s*:?\\s*(\\d+(?:\\.\\d+)?|\\.\\d+)(?:\\s*[-–]\\s*(\\d+(?:\\.\\d+)?|\\.\\d+))?",
            "\\b(\\d+(?:\\.\\d+)?|\\.\\d+)(?:\\s*[-–]\\s*(\\d+(?:\\.\\d+)?|\\.\\d+))?\\s*(?:credits?|crs?|hrs?)\\b",
        ]
        
        for pattern in creditPatterns {
            if let re = Self.cachedRegex(pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
                if let match = re.firstMatch(in: s, range: nsRange),
                   let creditString = creditsString(from: match, in: s) {
                    credits = creditString
                    // Remove the matched credit text from the string
                    if let matchRange = Range(match.range, in: s) {
                        s.removeSubrange(matchRange)
                        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    break
                }
            }
        }

        // Handle trailing fractional credits with no explicit "credits" token.
        // Example: "Independent Study .5" -> title="Independent Study", credits="0.5".
        if credits == nil {
            if let re = Self.cachedRegex("(?i)(?:\\s+|\\s*[-–]\\s*)(\\d?\\.\\d+)\\s*$") {
                let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
                if let match = re.firstMatch(in: s, range: nsRange),
                   match.numberOfRanges >= 2,
                   let r = Range(match.range(at: 1), in: s) {
                    let raw = String(s[r])
                    credits = normalizeCreditsValue(raw)
                    if let matchRange = Range(match.range, in: s) {
                        s.removeSubrange(matchRange)
                        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // Clean up the title
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing " - [digits]" pattern (e.g., "Masters Research Guidance - 6" → "Masters Research Guidance")
        s = s.replacingOccurrences(of: "\\s*[-–]\\s*\\d+$", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove HTML artifacts and special characters
        s = s.replacingOccurrences(of: "\\*+", with: "", options: .regularExpression) // Remove asterisks
        s = s.replacingOccurrences(of: "†+", with: "", options: .regularExpression) // Remove daggers
        s = s.replacingOccurrences(of: "‡+", with: "", options: .regularExpression) // Remove double daggers
        s = s.replacingOccurrences(of: "§+", with: "", options: .regularExpression) // Remove section marks
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing punctuation and separators
        s = s.replacingOccurrences(of: "[\\s\\-–:,;.]+$", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Some Modern Campus pages place logical connectors at the end of a bullet line
        // (e.g., "CHE 101 - General Chemistry Credits: 4 AND"). These are not part of the title.
        s = s.replacingOccurrences(of: "(?i)\\s*\\b(?:AND|OR)\\b\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[\\s\\-–:,;.]+$", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let title = s.isEmpty ? nil : s
        
        return (title, credits)
    }

    private func inferProgramTypeAndDegreeType(from programName: String, contextHint: String?) -> (cleanedName: String, programType: String, degreeType: String?) {
        let normalizedTitle = programName
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowerTitle = normalizedTitle.lowercased()
        let contextLower = (contextHint ?? "").lowercased()

        // Program typing: use page context when available.
        let contextSuggestsMinor = contextLower.contains("minor")
        let contextSuggestsCertificate = contextLower.contains("certificate") || contextLower.contains("micro-credential") || contextLower.contains("micro credential")
        let contextSuggestsMasters = contextLower.contains("master") || contextLower.contains("graduate")
        let contextSuggestsDoctorate = contextLower.contains("doctor") || contextLower.contains("phd")

        // Recognize degree abbreviations as standalone tokens.
        // (Keep this list tight and all-caps; matching is case-insensitive.)
        let degreeTokens = [
            "BA", "BS", "BFA", "BARCH", "BSE", "BE", "MUSB",
            "MA", "MS", "MFA", "MBA", "MPH", "MSW", "EDM",
            "JD", "PHD", "MD", "PHARMD", "DPT"
        ]

        func findDegreeTokens(in text: String) -> [String] {
            let pattern = "(?i)\\b(" + degreeTokens.joined(separator: "|") + ")\\b"
            guard let regex = Self.cachedRegex(pattern) else { return [] }
            let ns = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            return matches.map { ns.substring(with: $0.range(at: 1)).uppercased() }
        }

        let foundDegrees = findDegreeTokens(in: normalizedTitle)
        let uniqueDegrees = Array(Set(foundDegrees))

        // Identify combined degrees conservatively:
        // - must contain a slash
        // - AND must contain evidence of 2+ degree tokens (BS + MS, BA + JD, etc)
        // This prevents false positives like "Theatre Design/Technology BFA".
        let isCombined: Bool = {
            guard lowerTitle.contains("/") else { return false }

            // Explicit forms like "BS/MS" (with optional spaces)
            let combinedPattern = "(?i)\\b(" + degreeTokens.joined(separator: "|") + ")\\s*/\\s*(" + degreeTokens.joined(separator: "|") + ")\\b"
            if let regex = Self.cachedRegex(combinedPattern) {
                let ns = normalizedTitle as NSString
                if regex.firstMatch(in: normalizedTitle, options: [], range: NSRange(location: 0, length: ns.length)) != nil {
                    return true
                }
            }

            return uniqueDegrees.count >= 2
        }()

        // Choose program type with combined-degree taking precedence over doctorate/masters,
        // because many UB combined programs end in JD/PharmD/DPT.
        let programType: String
        if lowerTitle.contains("minor") || contextSuggestsMinor {
            programType = "Minor"
        } else if isCombined || lowerTitle.contains("combined") || lowerTitle.contains("dual") {
            programType = "Combined Degree"
        } else if lowerTitle.contains("certificate") || lowerTitle.contains("micro-credential") || lowerTitle.contains("micro credential") || contextSuggestsCertificate {
            programType = "Certificate"
        } else if lowerTitle.contains("ph.d") || lowerTitle.contains("doctor") || contextSuggestsDoctorate {
            programType = "Doctorate"
        } else if lowerTitle.contains("master") || lowerTitle.contains("m.s.") || lowerTitle.contains("m.a.") || contextSuggestsMasters {
            programType = "Master's"
        } else {
            programType = "Major"
        }

        // DegreeType + cleanedName behavior:
        // - For Majors: strip a trailing degree token into degreeType ("Accounting BS" -> name="Accounting", degreeType="BS")
        // - For Combined Degrees: keep the full title (so we preserve "... MS" / "... JD" etc)
        // - For other types: keep the full title as name.
        var cleanedName = normalizedTitle
        var degreeType: String? = nil

        if programType == "Major" {
            // Prefer a degree token at the very end.
            if let last = foundDegrees.last {
                let suffixPattern = "(?i)(?:,\\s*|\\s+)" + NSRegularExpression.escapedPattern(for: last) + "\\s*$"
                cleanedName = cleanedName
                    .replacingOccurrences(of: suffixPattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                degreeType = last
            }
        }

        if programType == "Minor" {
            cleanedName = cleanedName
                .replacingOccurrences(of: " Minor", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (cleanedName: cleanedName, programType: programType, degreeType: degreeType)
    }
    
    // MARK: - Build Department-to-College Mapping
    
    /// Scrapes the "Departments & Programs" page to build a mapping of departments to colleges.
    /// This page typically has a structure like:
    /// <h2>College Name</h2>
    /// <ul>
    ///   <li><a href="preview_entity.php">Department Name</a></li>
    ///   ...
    /// </ul>
    private func buildDepartmentToCollegeMapping(baseURL: URL, catalogID: Int) async throws {
        let logger = DebugLogger.shared
        
        // Try to find the "Departments & Programs" page in the sidebar
        let indexURL = baseURL.appendingPathComponent("index.php").appending("catoid", value: String(catalogID))
        let indexHTML = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
        let indexDoc = try SwiftSoup.parse(indexHTML, indexURL.absoluteString)
        
        // Look for "Departments" or "Programs" link in sidebar
        let sidebarLinks = try indexDoc.select("div.n2_links a, a.navbar")
        var departmentsPageURL: String?
        
        for link in sidebarLinks {
            let text = try link.text().lowercased()
            if text.contains("department") && (text.contains("program") || text.contains("&")) {
                departmentsPageURL = Self.forceCatoid(try link.attr("abs:href"), catalogID: catalogID)
                logger.log("🏛️ Found Departments & Programs page")
                break
            }
        }
        
        guard let deptPageURL = departmentsPageURL else {
            logger.log("⚠️ No 'Departments & Programs' page found, skipping mapping")
            return
        }
        
        // Fetch and parse the departments page
        let deptURL = Self.forceCatoid(deptPageURL, catalogID: catalogID)
        let deptHTML = try await ModernCampusEngine.fetchHTMLPublic(deptURL)
        let deptDoc = try SwiftSoup.parse(deptHTML, deptURL)
        
        // Find all h2/h3 headers (colleges) and their following department links/headers.
        // Strategy 1: h2 + preview_entity links (old/other catalogs)
        // Strategy 2: h3 (college) + h4 (department) + ul.program-list (UB graduate catalog)
        let body = deptDoc.body() ?? deptDoc
        var currentCollege: String?

        for element in try body.select("*") {
            let tagName = element.tagName()

            // Check for college headers (h2 or h3)
            if tagName == "h2" || tagName == "h3" {
                let collegeText = try element.text().normalizedCatalogText()
                if !collegeText.isEmpty {
                    currentCollege = collegeText
                    logger.log("🏛️ Found college (\(tagName)): \(collegeText)")
                }
                continue
            }

            // Check for department headers (h4)
            if tagName == "h4" {
                let deptText = try element.text().normalizedCatalogText()
                if !deptText.isEmpty && deptText.count >= 3 {
                    let cleanedDept = cleanDepartmentName(deptText)
                    // Map this department to the current college
                    if let college = currentCollege {
                        let canonicalCollege = college.normalizedCatalogText()
                        departmentToCollegeMapping[cleanedDept] = canonicalCollege
                        canonicalDepartmentNameByKey[normalizeDepartmentKey(cleanedDept)] = cleanedDept
                        logger.log("📍 Mapped dept (h4): \(cleanedDept) → \(canonicalCollege)")
                    }
                }
                continue
            }

            // Strategy 1: Old-style preview_entity links under h2
            guard let college = currentCollege else { continue }
            let departmentLinks = try element.select("a[href*=preview_entity]")
            if departmentLinks.isEmpty { continue }

            for link in departmentLinks {
                let deptName = try link.text().normalizedCatalogText()

                // Skip noise entries
                let lowerDept = deptName.lowercased()
                if deptName.isEmpty ||
                    lowerDept == "learn more about the" ||
                    lowerDept == "program office" ||
                    lowerDept == "program office:" ||
                    lowerDept.hasSuffix(" department page") ||
                    lowerDept.hasSuffix(" page") ||
                    deptName.count < 3 {
                    continue
                }

                // Clean up common variations
                let cleanedName = cleanDepartmentName(deptName)

                let canonicalCollege = college.normalizedCatalogText()
                departmentToCollegeMapping[cleanedName] = canonicalCollege
                canonicalDepartmentNameByKey[normalizeDepartmentKey(cleanedName)] = cleanedName
                logger.log("📍 Mapped dept (entity): \(cleanedName) → \(canonicalCollege)")
            }
        }
        
        logger.log("📊 Built mapping with \(departmentToCollegeMapping.count) departments")
    }

    /// UB-only: Walk the Departments & Programs directory, follow preview_entity pages,
    /// and map program URLs to (department, college).
    private func buildProgramOwnershipOverridesFromDepartmentEntities(baseURL: URL, catalogID: Int) async throws {
        let logger = DebugLogger.shared

        // Find the "Departments & Programs" (or similar) page in the sidebar.
        let indexURL = baseURL.appendingPathComponent("index.php").appending("catoid", value: String(catalogID))
        let indexHTML = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
        let indexDoc = try SwiftSoup.parse(indexHTML, indexURL.absoluteString)

        let sidebarLinks = try indexDoc.select("div.n2_links a, a.navbar, td.block_n2_and_content a, .block_n2_links a, table.block_n2_links a")

        // Pick the best-matching sidebar entry rather than the first match.
        // UB uses variants like "Departments & Programs" and "Department/Program".
        // Some professional catalogs may not expose a Departments directory link; in that case,
        // fall back to a Programs listing page (e.g., "Academic Programs", "Professional Programs").
        var best: (score: Int, href: String)?
        var bestProgramsFallback: (score: Int, href: String)?
        for link in sidebarLinks {
            let text = (try link.text()).lowercased()
            let rawHref = try link.attr("abs:href")
            guard !rawHref.isEmpty else { continue }
            let href = Self.forceCatoid(Self.normalizeToBaseHost(rawHref, baseURL: baseURL), catalogID: catalogID)

            // Prefer links that look like directory/listing pages.
            let isListingLike = href.contains("content.php") || href.contains("navoid=")

            if text.contains("department") {
                var score = 0
                if text.contains("departments & programs") { score += 20 }
                if text.contains("department/program") { score += 20 }
                if text.contains("department") && text.contains("program") { score += 10 }
                if isListingLike { score += 5 }
                score += 1

                if best == nil || score > best!.score {
                    best = (score: score, href: href)
                }
                continue
            }

            // Fallback: programs listing pages (Dental/Law/Medical often only show these).
            if text.contains("program") {
                var score = 0
                if text.contains("academic programs") { score += 10 }
                if text.contains("professional programs") { score += 10 }
                if text == "programs" { score += 6 }
                if isListingLike { score += 5 }
                score += 1

                if bestProgramsFallback == nil || score > bestProgramsFallback!.score {
                    bestProgramsFallback = (score: score, href: href)
                }
            }
        }

        let departmentsPageURL: String? = best?.href ?? bestProgramsFallback?.href
        guard let deptPageURL = departmentsPageURL else {
            return
        }

        logger.log("📌 UB ownership directory page: \(deptPageURL)")

        let deptURL = Self.forceCatoid(deptPageURL, catalogID: catalogID)
        let deptHTML = try await ModernCampusEngine.fetchHTMLPublic(deptURL)
        let deptDoc = try SwiftSoup.parse(deptHTML, deptURL)
        let body = deptDoc.body() ?? deptDoc

        // Some UB professional catalogs' program listing pages are flat (no h2/h3 ownership headers).
        // Use the catalog title as a reasonable fallback college/school label so programs don't end up nil.
        let fallbackCollege: String? = {
            if let h1 = (try? deptDoc.select("h1#acalog-content").first()),
               let t = try? h1.text().normalizedCatalogText(),
               !t.isEmpty {
                return t
            }
            if let span = (try? deptDoc.select("span.acalog_catalog_name").first()),
               let t = try? span.text().normalizedCatalogText(),
               !t.isEmpty {
                return t
            }
            return nil
        }()

        // Map preview_entity URLs (old style) and direct program URLs (new UB style)
        // Strategy 1: h2 + preview_entity links (follow entity pages to get programs)
        // Strategy 2: h3 + (optional h4) + preview_program links (directly extract from list)
        var entityLinks: [(entityName: String, entityURL: String, college: String)] = []
        var directProgramMappings: [(programURL: String, programName: String, dept: String, college: String)] = []
        var currentCollege: String?
        var currentDepartment: String?
        var seenDirectProgramKeys = Set<String>()

        func resolveAbsoluteURL(_ href: String, base: String) -> String? {
            let cleaned = Self.sanitizeAcalogURLString(href)
            guard !cleaned.isEmpty else { return nil }
            if let u = URL(string: cleaned), u.scheme != nil { return u.absoluteString }
            guard let baseURL = URL(string: base) else { return nil }
            return URL(string: cleaned, relativeTo: baseURL)?.absoluteURL.absoluteString
        }

        for element in try body.select("*") {
            let tagName = element.tagName()
            
            // Check for college headers (h2 or h3)
            if tagName == "h2" || tagName == "h3" {
                let college = try element.text().normalizedCatalogText()
                if !college.isEmpty {
                    currentCollege = college
                    currentDepartment = nil  // Reset department
                    logger.log("🏛️ Building overrides - found college (\(tagName)): \(college)")
                }
                continue
            }
            
            // Check for department headers (h4) - UB graduate catalog style
            if tagName == "h4" {
                let dept = try element.text().normalizedCatalogText()
                if !dept.isEmpty && dept.count >= 3 {
                    let cleanedDept = cleanDepartmentName(dept)
                    currentDepartment = cleanedDept
                    logger.log("📍 Found department (h4): \(cleanedDept)")
                }
                continue
            }
            
            // Allow flat directory pages (no headings) by using fallback college if needed.
            guard let college = (currentCollege ?? fallbackCollege) else { continue }

            // Important: only process the anchor node itself.
            // Scanning descendant anchors on container elements can see program links
            // before their corresponding h4 department heading is encountered.
            guard tagName == "a" else { continue }

            let hrefRaw = try element.attr("href")
            guard let abs = resolveAbsoluteURL(hrefRaw, base: deptURL) else { continue }

            if abs.contains("preview_program") {
                // Strategy 2: Direct program links.
                // Some UB catalogs (notably Grad) list certain programs directly under the school/college (h3)
                // without an intervening h4 department heading. In that case, treat the school/college as the
                // owning department for mapping purposes.
                let deptForPrograms = currentDepartment ?? college
                let programURL = Self.canonicalizeProgramURL(Self.forceCatoid(Self.normalizeToBaseHost(abs, baseURL: baseURL), catalogID: catalogID))
                let programName = try element.text().normalizedCatalogText()
                if programName.isEmpty { continue }

                let key = "\(programURL)|\(deptForPrograms)|\(college)"
                if !seenDirectProgramKeys.insert(key).inserted { continue }
                directProgramMappings.append((programURL: programURL, programName: programName, dept: deptForPrograms, college: college))
            } else if abs.contains("preview_entity") {
                // Strategy 1: Old-style preview_entity links
                let deptName = try element.text().normalizedCatalogText()
                if deptName.isEmpty || deptName.count < 3 { continue }

                let canonicalEntityURL = Self.canonicalizeEntityURL(Self.forceCatoid(Self.normalizeToBaseHost(abs, baseURL: baseURL), catalogID: catalogID))

                // Clean and canonicalize the entity/department name
                let cleanedEntity = cleanDepartmentName(deptName)
                let key = normalizeDepartmentKey(cleanedEntity)
                let canonicalEntity = canonicalDepartmentNameByKey[key] ?? cleanedEntity

                entityLinks.append((entityName: canonicalEntity, entityURL: canonicalEntityURL, college: college))
            }
        }

        // Add direct program mappings immediately (UB graduate catalog style)
        logger.log("📋 Found \(directProgramMappings.count) direct program mappings from h3+h4 structure")
        for mapping in directProgramMappings {
            if programOwnershipOverridesByURL[mapping.programURL] == nil {
                let refined = refineUBOwnership(programName: mapping.programName, department: mapping.dept, college: mapping.college)
                programOwnershipOverridesByURL[mapping.programURL] = (
                    department: refined.department ?? mapping.dept,
                    college: refined.college ?? mapping.college
                )
            }
            if programNameByURL[mapping.programURL] == nil && !mapping.programName.isEmpty {
                programNameByURL[mapping.programURL] = mapping.programName
            }
        }

        // De-dupe entity URLs (they can appear multiple times in some catalogs).
        var seenEntityURL = Set<String>()
        entityLinks = entityLinks.filter { seenEntityURL.insert($0.entityURL).inserted }

        if entityLinks.isEmpty {
            logger.log("🧭 UB ownership overrides complete: \(programOwnershipOverridesByURL.count) programs mapped")
            return
        }

        logger.log("🔄 Fetching \(entityLinks.count) entity pages for additional program mappings...")
        // Fetch entity pages concurrently and extract preview_program links.
        let entityFetchSemaphore = ModernCampusEngine.AsyncSemaphore(value: 8)
        await withTaskGroup(of: (tuples: [(programURL: String, programName: String, dept: String, college: String)], failed: Bool).self) { group in
            for entity in entityLinks {
                group.addTask {
                    await entityFetchSemaphore.acquire()
                    defer { entityFetchSemaphore.release() }

                    do {
                        let html = try await ModernCampusEngine.fetchHTMLPublic(entity.entityURL)
                        let doc = try SwiftSoup.parse(html, entity.entityURL)
                        let content = doc.body() ?? doc
                        let programAnchors = (try? content.select("a[href*=preview_program]")) ?? Elements()

                        var tuples: [(programURL: String, programName: String, dept: String, college: String)] = []
                        tuples.reserveCapacity(programAnchors.count)

                        for a in programAnchors {
                            let hrefRaw = try a.attr("href")
                            guard let abs = resolveAbsoluteURL(hrefRaw, base: entity.entityURL) else { continue }
                            let canonicalProgramURL = Self.canonicalizeProgramURL(Self.forceCatoid(Self.normalizeToBaseHost(abs, baseURL: baseURL), catalogID: catalogID))
                            let name = try a.text()
                                .replacingOccurrences(of: "\u{00A0}", with: " ")
                                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            tuples.append((programURL: canonicalProgramURL, programName: name, dept: entity.entityName, college: entity.college))
                        }
                        return (tuples: tuples, failed: false)
                    } catch {
                        return (tuples: [], failed: true)
                    }
                }
            }

            var failedEntityFetches = 0
            for await result in group {
                if result.failed {
                    failedEntityFetches += 1
                    continue
                }

                for t in result.tuples {
                    // Prefer first write; if duplicates exist, they should agree.
                    if programOwnershipOverridesByURL[t.programURL] == nil {
                        let refined = refineUBOwnership(programName: t.programName, department: t.dept, college: t.college)
                        programOwnershipOverridesByURL[t.programURL] = (
                            department: refined.department ?? t.dept,
                            college: refined.college ?? t.college
                        )
                    }
                    if programNameByURL[t.programURL] == nil, !t.programName.isEmpty {
                        programNameByURL[t.programURL] = t.programName
                    }
                }
            }

            if failedEntityFetches > 0 {
                logger.log("⚠️ UB entity page fetch failures: \(failedEntityFetches)/\(entityLinks.count) (using partial ownership mappings)")
            }
        }
        logger.log("🧭 UB ownership overrides built from entity pages: \(programOwnershipOverridesByURL.count)")
    }

    private func cleanDepartmentName(_ value: String) -> String {
        var s = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        s = s.replacingOccurrences(of: " department page", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " page", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = s.lowercased()
        if !lower.hasPrefix("department of") && lower.hasSuffix(" department") {
            s = s.replacingOccurrences(of: " department", with: "", options: [.caseInsensitive, .anchored, .backwards])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return s
    }

    // MARK: - Course Catalog Scraping
    
    /// Scrape the "Courses" catalog page to build a comprehensive course database.
    /// This provides a backup data source for course information (titles, credits, descriptions).
    ///
    /// For UB catalogs, the Courses page has navoid values:
    /// - catoid=17 (Undergraduate): navoid=862
    /// - catoid=19 (Graduate): navoid=1038
    /// - catoid=22 (Dental): navoid=1258
    /// - catoid=23 (Law): navoid=1282
    /// - catoid=24 (Medical): navoid=1294
    ///
    /// Strategy:
    /// 1. Find "Courses" link in sidebar
    /// 2. Visit courses page to get list of course links
    /// 3. Visit each course detail page (preview_course_nopop.php?catoid=X&coid=Y)
    /// 4. Parse course code, title, credits, description from <h1 id="course_preview_title">
    private func scrapeCoursesCatalog(baseURL: URL, catalogID: Int) async throws {
        let logger = DebugLogger.shared
        logger.logSection("📚 SCRAPING COURSE CATALOG")
        
        // 1. Find the Courses link in the sidebar
        let indexURL = baseURL.appendingPathComponent("index.php").appending("catoid", value: String(catalogID))
        let indexHTML = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
        let indexDoc = try SwiftSoup.parse(indexHTML, indexURL.absoluteString)
        
        let sidebarLinks = try indexDoc.select("div.n2_links a, a.navbar, td.block_n2_and_content a")
        var coursesPageURL: String?
        for link in sidebarLinks {
            let text = try link.text().lowercased()
            if text == "courses" || text == "course catalog" {
                coursesPageURL = Self.forceCatoid(try link.attr("abs:href"), catalogID: catalogID)
                break
            }
        }
        
        guard let coursesURL = coursesPageURL else {
            logger.log("⚠️ Could not find 'Courses' sidebar link for catalog \(catalogID)")
            return
        }
        
        logger.log("📖 Found Courses page: \(coursesURL)")
        
        // 2. Visit courses page to extract all course detail links
        let coursesHTML = try await ModernCampusEngine.fetchHTMLPublic(coursesURL)
        let coursesDoc = try SwiftSoup.parse(coursesHTML, coursesURL)
        
        // Extract all preview_course_nopop.php links
        let courseLinks = try coursesDoc.select("a[href*=preview_course_nopop]")
        logger.log("📝 Found \(courseLinks.count) course links on Courses page")
        
        // 3. Scrape course details — all links in one TaskGroup, concurrency capped by semaphore.
        // Avoids the stride "idle-worker" problem where the group waits for an entire batch
        // before launching the next one.
        var scrapedCount = 0

        let linksArray = courseLinks.array()
        let detailSemaphore = ModernCampusEngine.AsyncSemaphore(value: 12)

        try await withThrowingTaskGroup(of: CourseDetail?.self) { group in
            for linkElement in linksArray {
                let linkURL = (try? linkElement.attr("abs:href")) ?? ""
                guard !linkURL.isEmpty else { continue }

                group.addTask {
                    await detailSemaphore.acquire()
                    defer { detailSemaphore.release() }

                    let courseDetailURL = Self.forceCatoid(linkURL, catalogID: catalogID)

                    do {
                        let courseHTML = try await ModernCampusEngine.fetchHTMLPublic(courseDetailURL)

                        // autoreleasepool prevents SwiftSoup DOM trees from accumulating in memory
                        // when hundreds of tasks are in-flight simultaneously.
                        return try autoreleasepool {
                            let courseDoc = try SwiftSoup.parse(courseHTML, courseDetailURL)

                            // The <h1 id="course_preview_title"> contains: "CODE - Title"
                            guard let courseTitleH1 = try courseDoc.select("#course_preview_title").first() else {
                                return nil
                            }

                            // normalizedCatalogText() uses a statically compiled \s+ regex — no per-call overhead.
                            let h1Text = (try? courseTitleH1.text())?.normalizedCatalogText() ?? ""

                            // Parse course code from H1 text (e.g., "AAP 101SEM - Introduction to Arts Management")
                            guard let codeRe = Self.cachedRegex("^([A-Z]{2,6})\\s+(\\d{3})([A-Z]*)"),
                                  let codeMatch = codeRe.firstMatch(in: h1Text, range: NSRange(h1Text.startIndex..<h1Text.endIndex, in: h1Text)),
                                  codeMatch.numberOfRanges >= 3,
                                  let subjRange = Range(codeMatch.range(at: 1), in: h1Text),
                                  let numRange = Range(codeMatch.range(at: 2), in: h1Text)
                            else {
                                return nil
                            }

                            let subj = String(h1Text[subjRange])
                            let num = String(h1Text[numRange])
                            let code = "\(subj) \(num)"

                            var title: String?
                            let afterCode = String(h1Text[h1Text.index(h1Text.startIndex, offsetBy: codeMatch.range.upperBound)...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if let dashRange = afterCode.range(of: "-") {
                                title = String(afterCode[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if title?.isEmpty == true { title = nil }
                            }

                            guard let courseContainer = courseTitleH1.parent() else { return nil }
                            let containerText = (try? courseContainer.text())?.normalizedCatalogText() ?? ""

                            var credits: String?
                            if let creditsRe = Self.cachedRegex("Credits:\\s*(\\d+(?:\\s*-\\s*\\d+)?)", options: [.caseInsensitive]),
                               let creditsMatch = creditsRe.firstMatch(in: containerText, range: NSRange(containerText.startIndex..<containerText.endIndex, in: containerText)),
                               creditsMatch.numberOfRanges >= 2,
                               let creditsRange = Range(creditsMatch.range(at: 1), in: containerText) {
                                // Strip interior whitespace from ranges like "3 - 4" → "3-4"
                                credits = String(containerText[creditsRange])
                                    .components(separatedBy: .whitespaces).joined()
                            }

                            guard credits != nil else { return nil }
                            return CourseDetail(code: code, title: title, credits: credits)
                        }
                    } catch {
                        return nil
                    }
                }
            }

            var processedLinks = 0
            for try await courseDetail in group {
                processedLinks += 1
                if let detail = courseDetail {
                    courseDetailsByCode[detail.code] = detail
                    scrapedCount += 1
                    if scrapedCount <= 10 {
                        let title = detail.title ?? "no title"
                        let credits = detail.credits ?? "no credits"
                        logger.log("   📝 Cached: \(detail.code) - \(title) (\(credits) credits)")
                    }
                }
                if processedLinks % 50 == 0 || processedLinks == linksArray.count {
                    logger.log("   ✓ \(processedLinks)/\(linksArray.count) course pages processed (\(scrapedCount) cached)")
                }
            }
        }
        
        logger.log("✅ Course catalog scraping complete: \(courseDetailsByCode.count) courses cached")
        
        // Sample the cache to verify it has real data
        if !courseDetailsByCode.isEmpty {
            let sample = courseDetailsByCode.prefix(3)
            for (code, detail) in sample {
                let title = detail.title ?? "no title"
                let credits = detail.credits ?? "no credits"
                logger.log("   📚 Sample: \(code) - \(title) (\(credits) cr)")
            }
        }
    }

    // MARK: - Test hooks
    #if DEBUG
    /// Test-only helper: parse program requirements directly from a supplied HTML string.
    ///
    /// This allows deterministic tests that validate category splitting and ordering
    /// against real catalog HTML fixtures without making network requests.
    static func invoke_parseProgramRequirementsFromHTML_forTests(
        _ html: String,
        programURL: String
    ) throws -> [DegreeRequirement] {
        let parsed = try Self.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: programURL)
        return parsed.requirements
    }

    /// Test-only helper: parse (bucket -> entity links) and (entity -> program links) from HTML.
    static func invoke_parseUBOwnershipOverrides_forTests(
        departmentsAndProgramsHTML: String,
        entityHTMLByURL: [String: String],
        baseURL: String
    ) throws -> [String: (department: String, college: String)] {
        let doc = try SwiftSoup.parse(departmentsAndProgramsHTML, baseURL)
        let body = doc.body() ?? doc

        // Local normalization mirrors the actor's implementation.
        func normalize(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func canonicalProgramURL(_ url: String) -> String {
            Self.canonicalizeProgramURL(Self.sanitizeAcalogURLString(url))
        }

        func canonicalEntityURL(_ url: String) -> String {
            Self.canonicalizeEntityURL(Self.sanitizeAcalogURLString(url))
        }

        func resolveAbsoluteURL(_ href: String, base: String) -> String? {
            let cleaned = Self.sanitizeAcalogURLString(href)
            guard !cleaned.isEmpty else { return nil }
            if let u = URL(string: cleaned), u.scheme != nil { return u.absoluteString }
            guard let baseURL = URL(string: base) else { return nil }
            return URL(string: cleaned, relativeTo: baseURL)?.absoluteURL.absoluteString
        }

        // Keep the test hook consistent with production UB refinement behavior.
        func refineOwnership(programName: String, department: String, college: String) -> (department: String, college: String) {
            let deptLower = department.lowercased()
            let collegeLower = college.lowercased()
            let inSOM = deptLower.contains("school of management") || collegeLower.contains("school of management")
            guard inSOM else { return (department, college) }

            // Match production behavior: only refine when the "department" is really the
            // school-level container (i.e. no explicit h4 department was present).
            let deptIsSchoolLevel = deptLower.isEmpty || deptLower == collegeLower || deptLower.contains("school of management")
            guard deptIsSchoolLevel else { return (department, college) }

            let lead = normalize(
                (programName
                    .components(separatedBy: CharacterSet(charactersIn: ",/(-)"))
                    .first ?? "")
            )

            if lead.lowercased().hasPrefix("accounting") {
                let fixedCollege = college.isEmpty ? "School of Management" : college
                return (department: "Accounting", college: fixedCollege)
            }

            return (department, college)
        }

        var currentCollege: String?
        var currentDepartment: String?
        var entities: [(dept: String, url: String, college: String)] = []
        var overrides: [String: (department: String, college: String)] = [:]

        // Canonicalize the entity HTML lookup so callers can provide raw or canonical keys.
        var canonicalEntityHTMLByURL: [String: String] = [:]
        canonicalEntityHTMLByURL.reserveCapacity(entityHTMLByURL.count)
        for (url, html) in entityHTMLByURL {
            canonicalEntityHTMLByURL[url] = html
            canonicalEntityHTMLByURL[Self.sanitizeAcalogURLString(url)] = html
            canonicalEntityHTMLByURL[canonicalEntityURL(url)] = html
        }

        // Pass 1: parse direct program links (grad-style) and collect entity links (old-style).
        for element in try body.select("*") {
            let tag = element.tagName()
            if tag == "h2" || tag == "h3" {
                let c = normalize(try element.text())
                currentCollege = c.isEmpty ? nil : c
                currentDepartment = nil
                continue
            }
            if tag == "h4" {
                let d = normalize(try element.text())
                currentDepartment = d.isEmpty ? nil : d
                continue
            }
            guard let college = currentCollege else { continue }

            // Important: only process the anchor node itself.
            // Scanning descendant anchors on container elements causes us to see program links
            // before their corresponding h4 department heading is encountered.
            guard tag == "a" else { continue }

            let hrefRaw = try element.attr("href")
            guard let href = resolveAbsoluteURL(hrefRaw, base: baseURL) else { continue }

            if href.contains("preview_program") {
                // Direct program links: if no h4, treat the college/school as the department.
                let deptForPrograms = currentDepartment ?? college
                let programName = normalize(try element.text())
                let refined = refineOwnership(programName: programName, department: deptForPrograms, college: college)
                let purl = canonicalProgramURL(href)
                if overrides[purl] == nil {
                    overrides[purl] = (department: refined.department, college: refined.college)
                }
            } else if href.contains("preview_entity") {
                // Old-style entity links (follow entity pages below).
                let dept = normalize(try element.text())
                if dept.isEmpty { continue }
                entities.append((dept: dept, url: canonicalEntityURL(href), college: college))
            }
        }

        // Pass 2: follow entity pages to map programs.
        for e in entities {
            guard let entityHTML = canonicalEntityHTMLByURL[e.url] else { continue }
            let entityDoc = try SwiftSoup.parse(entityHTML, e.url)
            let entityBody = entityDoc.body() ?? entityDoc
            for a in (try? entityBody.select("a[href*=preview_program]")) ?? Elements() {
                let hrefRaw = try a.attr("href")
                guard let href = resolveAbsoluteURL(hrefRaw, base: e.url) else { continue }
                let programName = normalize(try a.text())
                let refined = refineOwnership(programName: programName, department: e.dept, college: e.college)
                let purl = canonicalProgramURL(href)
                if overrides[purl] == nil {
                    overrides[purl] = (department: refined.department, college: refined.college)
                }
            }
        }
        return overrides
    }
    #endif

    /// Normalizes department names for fuzzy-but-deterministic matching.
    /// This intentionally mirrors CoreData's normalization rules enough to handle
    /// typos/plurals/parentheticals and whitespace quirks.
    private func normalizeDepartmentKey(_ value: String) -> String {
        // First normalize general formatting and obvious ModernCampus quirks.
        var normalized = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

    // Repair a small set of known upstream typos/variants (UB catalog has these in-page).
    // IMPORTANT: use regex word-boundaries so we don't accidentally double-apply.
    // Keep this list small and deterministic; it should only correct clear misspellings.
    let repairs: [(pattern: String, replacement: String)] = [
            // Simple misspellings observed on UB program pages.
            ("\\bsustainabillity\\b", "sustainability"),
            ("\\bcrimonology\\b", "criminology"),

            // Program pages sometimes include singular "Language" and even misspell it,
            // but the canonical department directory uses "Romance Languages and Literatures".
            // Map both variants directly to the canonical wording so we hit the directory key.
            ("\\bromance\\s+langauge\\b", "romance languages and literatures"),
            ("\\bromance\\s+language\\b", "romance languages and literatures"),
            ("\\bromance\\s+languages\\s+and\\s+literature\\b", "romance languages and literatures"),

            // Program pages sometimes show the short department label, but the directory
            // uses a longer canonical name.
            // UB program pages sometimes omit the parenthetical.
            // Only expand when the "engineering science" token isn't already present.
            ("\\bengineering\\s+education\\b(?![^a-z0-9]+engineering\\s+science\\b)", "engineering education engineering science"),

            // UB program pages often use the short label.
            // Only expand when the "criminology" token isn't already present.
            ("\\bsociology\\b(?![^a-z0-9]+and[^a-z0-9]+criminology\\b)", "sociology and criminology"),

            // Minor naming variations.
            ("\\bsocial\\s+sciences\\s+interdisciplinary\\b", "social science interdisciplinary"),
            ("\\bsocial\\s+studies\\s+interdisciplinary\\b", "social science interdisciplinary")
        ]

        for (pattern, replacement) in repairs {
            normalized = normalized.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        // Strip common artifacts
        let removeList = [
            " department page",
            " department",
            " program",
            " office",
            " page"
        ]
        for term in removeList {
            if normalized.hasSuffix(term) {
                normalized = String(normalized.dropLast(term.count))
            }
        }
        if normalized.hasPrefix("department of ") {
            normalized = String(normalized.dropFirst("department of ".count))
        }

        return normalized
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Sidebar Probe
    
    private struct SidebarLink {
        let text: String
        let href: String
    }
    
    private func probeSidebarForContainers(baseURL: URL, catalogID: Int) async throws -> [SidebarLink] {
        let logger = DebugLogger.shared
        // Construct the index URL
        let indexURL = baseURL.appendingPathComponent("index.php").appending("catoid", value: String(catalogID))
        logger.log("🔍 Probing sidebar for catalog \(catalogID): \(indexURL.absoluteString)")
        let html = try await ModernCampusEngine.fetchHTMLPublic(indexURL.absoluteString)
        let doc = try SwiftSoup.parse(html, indexURL.absoluteString) // Use base URL for resolving relative links
        
        var results: [SidebarLink] = []
        
        // Select all links in the sidebar
        // Modern Campus uses various classes: n2_links, navbar, or older table-based layouts
        let sidebarLinks = try doc.select("div.n2_links a, a.navbar, td.block_n2_and_content a, .block_n2_links a, table.block_n2_links a")
        logger.log("🔍 Found \(sidebarLinks.array().count) total sidebar links")
        
        // Log first 20 sidebar links for diagnostics
        for (idx, link) in sidebarLinks.array().prefix(20).enumerated() {
            let text = try link.text().normalizedCatalogText()
            let href = try link.attr("abs:href")
            logger.log("   Sidebar[\(idx)]: '\(text)' → \(href)")
        }
        
        for link in sidebarLinks {
            let text = try link.text().normalizedCatalogText()
            guard !text.isEmpty else { continue }
            
            let href = Self.forceCatoid(try link.attr("abs:href"), catalogID: catalogID)
            
            // Filter: We want pages that likely contain lists of programs/departments.
            // We look for keywords in the TEXT, but we validate the URL structure.
            let lowerText = text.lowercased()
            
            let isCandidate = lowerText.contains("major") ||
                              lowerText.contains("minor") ||
                              lowerText.contains("degree") ||
                              lowerText.contains("program") ||
                              lowerText.contains("department") ||
                              lowerText.contains("school") ||
                              lowerText.contains("college") ||
                              lowerText.contains("academic") ||
                              lowerText.contains("undergraduate") ||
                              lowerText.contains("graduate")
            
            // Ensure it's a content page (navoid) and not a popup or external link
            if isCandidate && href.contains("navoid=") {
                logger.log("   ✓ Container candidate: '\(text)'")
                results.append(SidebarLink(text: text, href: href))
            }
        }
        
        logger.log("🔍 Selected \(results.count) container pages for catalog \(catalogID)")
        
        // Fallback: If we found no container pages, try scanning ALL sidebar links for program links
        if results.isEmpty {
            logger.log("⚠️ No container pages found, will scan all sidebar links as fallback")
            for link in sidebarLinks {
                let text = try link.text().normalizedCatalogText()
                guard !text.isEmpty else { continue }
                let href = Self.forceCatoid(try link.attr("abs:href"), catalogID: catalogID)
                if href.contains("navoid=") {
                    results.append(SidebarLink(text: text, href: href))
                }
            }
            logger.log("🔍 Fallback: added \(results.count) pages to scan")
        }
        return results
    }
    
    // MARK: - Stream Scraper (The Core Logic)
    
    private func scrapeStream(url: String, defaultContext: String, catalogID: Int) async throws -> [HierarchyItem] {
        let logger = DebugLogger.shared
        
        guard let validURL = URL(string: url) else { 
            logger.log("⚠️ Invalid URL: \(url)")
            return [] 
        }
        
        let html = try await ModernCampusEngine.fetchHTMLPublic(validURL.absoluteString)
        logger.log("📥 Fetched HTML (\(html.count) chars)")
        
        // Parse with base URL so relative links can be resolved
        let doc = try SwiftSoup.parse(html, validURL.absoluteString)
        
        // Restrict to main content to avoid pulling program links from the sidebar/nav.
        // For ModernCampus/Acalog, content is typically in td.block_content or similar containers.
        let content: Element = {
            // First, try to find the table that contains program links
            // This is usually table.table_default on program listing pages
            if let table = (try? doc.select("table.table_default").first()) {
                logger.log("📋 Selected content area: table.table_default")
                return table
            }
            // Try the main content table cell (most common for ModernCampus)
            if let main = (try? doc.select("td.block_content").first()) {
                logger.log("📋 Selected content area: td.block_content")
                return main
            }
            // Try div-based content areas
            if let main = (try? doc.select("div.block_content").first()) {
                logger.log("📋 Selected content area: div.block_content")
                return main
            }
            // Try generic content IDs
            if let main = (try? doc.select("#content, #gateway-page-content").first()) {
                logger.log("📋 Selected content area: #content or #gateway-page-content")
                return main
            }
            // Last resort: use body but log a warning since this includes sidebar
            if let body = doc.body() {
                logger.log("📋 Selected content area: body (fallback - may include sidebar)")
                return body
            }
            logger.log("⚠️ No content area found, using entire document")
            return doc
        }()
        logger.log("📋 Searching for links in: \(content.tagName()), text preview: \(try (content.text().prefix(200)))")

        // We intentionally do a *stream parse* over the content block so we can associate
        // school/college headings with the programs that follow them.
        // This is critical for UB Graduate Programs pages like:
        // https://catalogs.buffalo.edu/content.php?catoid=19&navoid=1040
        let stream = (try? content.getAllElements()) ?? Elements()
        logger.log("📋 Stream contains \(stream.array().count) elements to parse")
        
        // Count how many are links with preview_program.php
        let programLinks = stream.array().filter { el in
            guard el.tagName().lowercased() == "a" else { return false }
            let href = (try? el.attr("abs:href")) ?? ""
            return href.contains(programLinkPattern)
        }
        logger.log("📋 Found \(programLinks.count) program links (preview_program.php) in content")
        
        var currentCollege: String? = nil
        var currentDepartment: String? = nil

        func looksLikeCollegeHeader(_ raw: String) -> Bool {
            let t = raw.normalizedCatalogText()
            if t.isEmpty { return false }
            if isMatch(t, patterns: collegePatterns) { return true }
            let lower = t.lowercased()
            return lower.hasPrefix("school of ") || lower.hasPrefix("college of ") || lower.contains(" school of ") || lower.contains(" college of ")
        }

        func looksLikeDepartmentHeader(_ raw: String) -> Bool {
            let t = raw.normalizedCatalogText()
            if t.isEmpty { return false }
            if isMatch(t, patterns: departmentPatterns) { return true }
            let lower = t.lowercased()
            return lower.hasPrefix("department of ") || lower.hasSuffix(" department") || lower.contains(" department of ")
        }

        struct PendingProgramItem {
            let programName: String
            let canonicalProgramURL: String
            let fixedHref: String
            let seedDepartment: String?
            let seedCollege: String?
        }

        var pendingPrograms: [PendingProgramItem] = []
        pendingPrograms.reserveCapacity(256)

        for el in stream {
            let tag = el.tagName().lowercased()

            if tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" {
                let heading = ((try? el.text()) ?? "").normalizedCatalogText()
                guard !heading.isEmpty else { continue }

                // Prefer college/school headings; when we see one, reset the department context.
                if looksLikeCollegeHeader(heading) {
                    currentCollege = heading
                    currentDepartment = nil
                    continue
                }

                if looksLikeDepartmentHeader(heading) {
                    currentDepartment = heading
                    continue
                }

                // UB Graduate Catalog: h3 = school/college, h4 = department
                // If we have a college context and see an h4, treat it as a department
                // even if it doesn't match explicit department patterns.
                if tag == "h4", currentCollege != nil {
                    currentDepartment = heading
                    continue
                }

                continue
            }

            guard tag == "a" else { continue }
            let rawHref = (try? el.attr("abs:href")) ?? ""
            guard !rawHref.isEmpty, rawHref.contains(programLinkPattern) else { continue }

            let programName = ((try? el.text()) ?? "").normalizedCatalogText()
            guard !programName.isEmpty else { continue }

            // IMPORTANT: make `catoid` explicit to avoid session-default fallbacks.
            // Use the *catalogID we were invoked with* (do not rely on container URL parsing).
            let fixedHref = Self.forceCatoid(Self.normalizeToBaseHost(rawHref, baseURL: validURL), catalogID: catalogID)
            let canonicalProgramURL = Self.canonicalizeProgramURL(fixedHref)

            // Prefer ownership from the listing page hierarchy (Programs tab).
            // If the page only provides school/college headings, treat that as the effective "department"
            // for dropdown + grouping purposes.
            var department = (currentDepartment ?? currentCollege)?.normalizedCatalogText()
            var college = currentCollege?.normalizedCatalogText()

            // UB-only: if we have a directory-derived ownership override for this program URL,
            // prefer it over page hierarchy (sometimes more specific).
            if let override = programOwnershipOverridesByURL[canonicalProgramURL] {
                department = override.department.normalizedCatalogText()
                college = override.college.normalizedCatalogText()
            }

            pendingPrograms.append(
                PendingProgramItem(
                    programName: programName,
                    canonicalProgramURL: canonicalProgramURL,
                    fixedHref: fixedHref,
                    seedDepartment: department,
                    seedCollege: college
                )
            )
        }

        // Resolve missing ownerships concurrently (bounded) to avoid serial page fetches
        // on catalogs where heading-based ownership is sparse.
        let unresolved = pendingPrograms.filter { ($0.seedDepartment ?? "").isEmpty && ($0.seedCollege ?? "").isEmpty }
        var unresolvedProgramURLToFixedHref: [String: String] = [:]
        unresolvedProgramURLToFixedHref.reserveCapacity(unresolved.count)
        for pending in unresolved {
            if unresolvedProgramURLToFixedHref[pending.canonicalProgramURL] == nil {
                unresolvedProgramURLToFixedHref[pending.canonicalProgramURL] = pending.fixedHref
            }
        }

        var extractedByProgramURL: [String: (department: String?, college: String?)] = [:]
        extractedByProgramURL.reserveCapacity(unresolvedProgramURLToFixedHref.count)

        if !unresolvedProgramURLToFixedHref.isEmpty {
            let ownershipFetchSemaphore = ModernCampusEngine.AsyncSemaphore(value: 8)
            var failedOwnershipFetches = 0

            await withTaskGroup(of: (String, String?, String?, Bool).self) { group in
                for (programURL, fixedHref) in unresolvedProgramURLToFixedHref {
                    group.addTask { [self] in
                        await ownershipFetchSemaphore.acquire()
                        defer { ownershipFetchSemaphore.release() }

                        do {
                            let extracted = try await self.extractDepartmentAndCollege(from: fixedHref)
                            return (
                                programURL,
                                extracted.department?.normalizedCatalogText(),
                                extracted.college?.normalizedCatalogText(),
                                false
                            )
                        } catch {
                            return (programURL, nil, nil, true)
                        }
                    }
                }

                for await (programURL, department, college, didFail) in group {
                    if didFail {
                        failedOwnershipFetches += 1
                    }
                    extractedByProgramURL[programURL] = (department, college)
                }
            }

            if failedOwnershipFetches > 0 {
                logger.log("⚠️ Ownership fallback fetch failures: \(failedOwnershipFetches)/\(unresolvedProgramURLToFixedHref.count) (continuing with available data)")
            }
        }

        var results: [HierarchyItem] = []
        results.reserveCapacity(pendingPrograms.count)

        for pending in pendingPrograms {
            var department = pending.seedDepartment
            var college = pending.seedCollege

            if (department ?? "").isEmpty && (college ?? "").isEmpty,
               let extracted = extractedByProgramURL[pending.canonicalProgramURL] {
                department = extracted.department
                college = extracted.college
            }

            // Canonicalize department names via directory map when possible.
            if let dept = department, !dept.isEmpty {
                let key = normalizeDepartmentKey(dept)
                if let canonical = canonicalDepartmentNameByKey[key] {
                    department = canonical
                    if let mappedCollege = departmentToCollegeMapping[canonical] {
                        college = mappedCollege
                    }
                }
            }

            // UB-only: final conservative refinement pass.
            if validURL.host?.contains("buffalo.edu") == true {
                let refined = refineUBOwnership(programName: pending.programName, department: department, college: college)
                department = refined.department
                college = refined.college
            }

            let inferred = inferProgramTypeAndDegreeType(from: pending.programName, contextHint: defaultContext)
            let item = HierarchyItem(
                programName: inferred.cleanedName,
                programURL: pending.canonicalProgramURL,
                programType: inferred.programType,
                college: (college ?? "").isEmpty ? nil : college,
                department: (department ?? "").isEmpty ? nil : department,
                degreeType: inferred.degreeType
            )
            results.append(item)
        }
        
        logger.log("✅ Extracted \(results.count) programs from this page")
        return results
    }
    
    // MARK: - Extract Department/College from Program Detail Page
    
    private func extractDepartmentAndCollege(from programURL: String) async throws -> (department: String?, college: String?) {
        let cacheKey = Self.canonicalizeProgramURL(programURL)
        if let cached = ownershipByProgramURLCache[cacheKey] {
            return cached
        }

        // Fetch the program detail page
        let html = try await ModernCampusEngine.fetchHTMLPublic(programURL)
        let doc = try SwiftSoup.parse(html, programURL)
        
        let logger = DebugLogger.shared
        var department: String?
        var college: String?
        
        logger.log("🔍 [DeptExtract] URL: \(programURL)")
        
        // Strategy 1: Look for Stony Brook-style structured info
        // "<div><strong>Department of Anthropology, College of Arts and Sciences</strong></div>"
        if let descDiv = try doc.select("div.program_description").first() {
            let strongTags = try descDiv.select("strong")
            logger.log("🔍 [DeptExtract] Found \(strongTags.count) <strong> tags in program_description")
            
            for strong in strongTags {
                let text = try strong.text().normalizedCatalogText()
                logger.log("🔍 [DeptExtract] Checking strong tag: '\(text)'")
                
                // Skip noise entries
                let lowerText = text.lowercased()
                if lowerText == "program office" || 
                   lowerText == "program office:" ||
                   lowerText.isEmpty {
                    logger.log("🔍 [DeptExtract] Skipping noise entry")
                    continue
                }
                
                // Check if it matches "Department of X, College of Y" pattern
                if text.contains(",") {
                    let parts = text.components(separatedBy: ",").map { $0.normalizedCatalogText() }
                    if parts.count >= 2 {
                        // First part might be department
                        if isMatch(parts[0], patterns: departmentPatterns) || parts[0].lowercased().contains("department") {
                            department = parts[0]
                        }
                        // Second part might be college (extract from semicolon if present)
                        var collegePart = parts[1]
                        if collegePart.contains(";") {
                            // Handle "Department X; College Y" format
                            let semicolonParts = collegePart.components(separatedBy: ";").map { $0.normalizedCatalogText() }
                            if semicolonParts.count >= 2 {
                                collegePart = semicolonParts[1]
                            }
                        }
                        if isMatch(collegePart, patterns: collegePatterns) || collegePart.lowercased().contains("college") || collegePart.lowercased().contains("school") {
                            college = collegePart
                        }
                    }
                } 
                // Handle semicolon-separated format: "Department X; College Y"
                else if text.contains(";") {
                    let parts = text.components(separatedBy: ";").map { $0.normalizedCatalogText() }
                    if parts.count >= 2 {
                        // First part is department
                        if isMatch(parts[0], patterns: departmentPatterns) || parts[0].lowercased().contains("department") {
                            department = parts[0]
                        }
                        // Second part is college
                        if isMatch(parts[1], patterns: collegePatterns) || parts[1].lowercased().contains("college") || parts[1].lowercased().contains("school") {
                            college = parts[1]
                        }
                    }
                }
                else if isMatch(text, patterns: departmentPatterns) {
                    department = text
                } else if isMatch(text, patterns: collegePatterns) {
                    college = text
                }
                
                // If we found both, we're done
                if department != nil && college != nil {
                    logger.log("✅ [DeptExtract] Found both - dept: '\(department!)', college: '\(college!)'")
                    break
                }
            }
        } else {
            logger.log("⚠️ [DeptExtract] No program_description div found")
        }
        
        // Strategy 2: Look for UB-style department link
        // "Visit the <a href="preview_entity.php...">Mechanical and Aerospace Engineering department page</a>"
        if department == nil {
            let entityLinks = try doc.select("a[href*=preview_entity]")
            logger.log("🔍 [DeptExtract] Strategy 2: Found \(entityLinks.count) entity links")
            
            for link in entityLinks {
                let linkText = try link.text().normalizedCatalogText()
                logger.log("🔍 [DeptExtract] Checking entity link: '\(linkText)'")
                
                // Skip obvious noise entries
                let lowerLink = linkText.lowercased()
                if lowerLink == "learn more about the" || 
                   lowerLink == "program office" ||
                   lowerLink == "program office:" ||
                   lowerLink.isEmpty {
                    continue
                }
                
                // Extract department name from "X department page" or "Department of X"
                if linkText.lowercased().contains("department") {
                    // Remove "department page" suffix
                    var cleanedText = linkText
                        .replacingOccurrences(of: " department page", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: " page", with: "", options: .caseInsensitive)
                        .normalizedCatalogText()
                    
                    // If it's JUST "department" or "Department", skip it
                    if cleanedText.lowercased() == "department" {
                        continue
                    }
                    
                    // Some pages might say "Economics department" - normalize these
                    if !cleanedText.lowercased().hasPrefix("department of") &&
                       cleanedText.lowercased().hasSuffix(" department") {
                        // "Economics department" -> "Economics"
                        cleanedText = cleanedText.replacingOccurrences(of: " department", with: "", options: .caseInsensitive)
                            .normalizedCatalogText()
                    }
                    
                    if !cleanedText.isEmpty && cleanedText.count > 3 { // Reasonable minimum length
                        department = cleanedText
                        break // Take the first valid match
                    }
                }
            }
        }
        
        // Strategy 3: Use dynamic department-to-college mapping
        // If we have a department but no college, check our mapping (built from "Departments & Programs" page)
        if college == nil && department != nil {
            college = departmentToCollegeMapping[department!]
        }

        // Strategy 4: Canonicalize department names using the mapping.
        // Even when we found a department string, it may be a typo/variant like
        // "Romance Langauge" vs "Romance Languages and Literatures".
        // If we can map the normalized key to a canonical directory name, use it.
        if let dept = department {
            let key = normalizeDepartmentKey(dept)
            if let canonical = canonicalDepartmentNameByKey[key] {
                department = canonical
                // Also prefer the mapped college (directory grouping) when available.
                if let mappedCollege = departmentToCollegeMapping[canonical] {
                    college = mappedCollege
                }
            }
        }
        
        // FINAL CLEANUP: Clean all department names before returning
        if var dept = department {
            // Normalize whitespace first (ModernCampus often uses NBSP \u00A0)
            dept = dept.normalizedCatalogText()

            // Remove common artifacts first
            dept = dept.replacingOccurrences(of: " department page", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " page", with: "", options: .caseInsensitive)
                .normalizedCatalogText()
            
            // Now check the cleaned string for " department" suffix
            let cleanedLower = dept.lowercased()
            
            // Remove " department" suffix UNLESS it's "Department of X"
            if !cleanedLower.hasPrefix("department of") && cleanedLower.hasSuffix(" department") {
                dept = dept.replacingOccurrences(of: " department", with: "", options: [.caseInsensitive, .anchored, .backwards])
                    .normalizedCatalogText()
            }
            
            // Filter out noise
            if dept.isEmpty || dept.lowercased() == "learn more about the" || 
               dept.lowercased() == "program office" || dept.count < 3 {
                department = nil
            } else {
                department = dept
            }
        }

        college = college?.normalizedCatalogText()
        
        let result: (department: String?, college: String?) = (department, college)

        // Keep cache bounded for long sessions.
        if ownershipByProgramURLCache.count >= 4096 {
            ownershipByProgramURLCache.removeAll(keepingCapacity: true)
        }
        if result.department != nil || result.college != nil {
            ownershipByProgramURLCache[cacheKey] = result
        }

        return result
    }
    
    // MARK: - Helpers
    
    private func isMatch(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}

// MARK: - URL Extension
extension URL {
    nonisolated func appending(_ queryItem: String, value: String?) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: queryItem, value: value))
        components.queryItems = queryItems
        return components.url ?? self
    }
}
