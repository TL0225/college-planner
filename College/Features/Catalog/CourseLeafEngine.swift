// CourseLeafEngine.swift
// Feature: Catalog
// Purpose: Catalog module — CrawlOutput.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit
import SwiftSoup

enum CourseLeafEngine {
    struct CrawlOutput: Sendable {
        let courses: [CatalogCourse]
        let programs: [ScrapedProgram]
        let sourceSignature: String
        let dominantLayoutProfileID: String?
        let layoutConfidence: Double?
    }

    struct PageParseResult: Sendable {
        let courses: [CatalogCourse]
        let programs: [ScrapedProgram]
        let layoutProfileID: String?
        let layoutConfidence: Double
    }

    private static var session: URLSession { CourseLeafXMLClient.session }

    /// Legacy crawl parse for offline parity diff (ignores `documentIREnabled`).
    static func parseCatalogPageLegacy(xml: String, pageURL: URL, schoolID: String) -> PageParseResult {
        let config = CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID)
        let courses = parseCourses(from: xml, pageURL: pageURL, config: config)
        let programs = parsePrograms(
            from: xml,
            pageURL: pageURL,
            config: config,
            parseRequirements: false,
            schoolID: schoolID
        )
        return PageParseResult(courses: courses, programs: programs, layoutProfileID: nil, layoutConfidence: 0)
    }

    /// Parses a single CourseLeaf `index.xml` page. Used by golden fixture tests (always IR pipeline).
    static func parseCatalogPage(xml: String, pageURL: URL, schoolID: String) -> PageParseResult {
        CourseLeafIRPipeline.parsePage(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID,
            catalogVersionID: schoolID,
            parseRequirements: false
        )
    }

    static func crawlCatalog(
        baseURL rawURL: String,
        schoolID: String,
        parseRequirements: Bool = false,
        preferredPageURLs: [URL]? = nil,
        catalogVersionIDByPageURL: [String: String]? = nil
    ) async throws -> CrawlOutput {
        if CatalogPlatformFlags.documentIREnabled {
            return try await crawlCatalogViaIR(
                rawBaseURL: rawURL,
                schoolID: schoolID,
                parseRequirements: parseRequirements,
                preferredPageURLs: preferredPageURLs,
                catalogVersionIDByPageURL: catalogVersionIDByPageURL
            )
        }
        return try await crawlCatalogLegacy(
            rawBaseURL: rawURL,
            schoolID: schoolID,
            parseRequirements: parseRequirements,
            preferredPageURLs: preferredPageURLs
        )
    }

    private static func crawlCatalogViaIR(
        rawBaseURL: String,
        schoolID: String,
        parseRequirements: Bool,
        preferredPageURLs: [URL]?,
        catalogVersionIDByPageURL: [String: String]?
    ) async throws -> CrawlOutput {
        guard let normalizedBase = normalizeBaseURL(rawBaseURL) else {
            throw ScraperError.invalidURL
        }

        let pageURLs: [URL]
        if let preferred = preferredPageURLs, !preferred.isEmpty {
            pageURLs = preferred
        } else {
            pageURLs = try await sitemapPageURLs(baseURL: normalizedBase)
        }
        var discoveredCourses: [CatalogCourse] = []
        var discoveredPrograms: [ScrapedProgram] = []
        var signatureMaterial: [String] = []
        signatureMaterial.reserveCapacity(pageURLs.count)
        var layoutVotes: [String: Int] = [:]
        var layoutConfidenceSum: [String: Double] = [:]

        for pageURL in pageURLs {
            let indexURL = normalizedIndexURL(from: pageURL)
            do {
                let xml = try await fetchXML(from: indexURL)
                signatureMaterial.append(indexURL.absoluteString)
                signatureMaterial.append(String(xml.prefix(4096)))
                let versionID = catalogVersionIDByPageURL?[pageURL.absoluteString] ?? schoolID
                let parsed = await CourseLeafIRPipeline.parsePageAsync(
                    xml: xml,
                    pageURL: pageURL,
                    schoolID: schoolID,
                    catalogVersionID: versionID,
                    parseRequirements: parseRequirements
                )
                discoveredCourses.append(contentsOf: parsed.courses)
                discoveredPrograms.append(contentsOf: parsed.programs)
                if let profileID = parsed.layoutProfileID {
                    layoutVotes[profileID, default: 0] += 1
                    layoutConfidenceSum[profileID, default: 0] += parsed.layoutConfidence
                }
            } catch {
                continue
            }
        }

        let dominantLayout = layoutVotes.max(by: { $0.value < $1.value })?.key
        let layoutConfidence: Double? = {
            guard let dominantLayout, let votes = layoutVotes[dominantLayout], votes > 0 else { return nil }
            return (layoutConfidenceSum[dominantLayout] ?? 0) / Double(votes)
        }()

        return CrawlOutput(
            courses: deduplicateCourses(discoveredCourses),
            programs: deduplicatePrograms(discoveredPrograms),
            sourceSignature: computeSignature(from: signatureMaterial, schoolID: schoolID),
            dominantLayoutProfileID: dominantLayout,
            layoutConfidence: layoutConfidence
        )
    }

    private static func crawlCatalogLegacy(
        rawBaseURL: String,
        schoolID: String,
        parseRequirements: Bool,
        preferredPageURLs: [URL]? = nil
    ) async throws -> CrawlOutput {
        guard let normalizedBase = normalizeBaseURL(rawBaseURL) else {
            throw ScraperError.invalidURL
        }
        let crawlConfig = CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID)

        let pageURLs: [URL]
        if let preferred = preferredPageURLs, !preferred.isEmpty {
            pageURLs = preferred
        } else {
            pageURLs = try await sitemapPageURLs(baseURL: normalizedBase)
        }

        var discoveredCourses: [CatalogCourse] = []
        var discoveredPrograms: [ScrapedProgram] = []
        var signatureMaterial: [String] = []
        signatureMaterial.reserveCapacity(pageURLs.count)

        for pageURL in pageURLs {
            let indexURL = normalizedIndexURL(from: pageURL)
            do {
                let xml = try await fetchXML(from: indexURL)
                signatureMaterial.append(indexURL.absoluteString)
                signatureMaterial.append(String(xml.prefix(4096)))
                discoveredCourses.append(contentsOf: parseCourses(from: xml, pageURL: pageURL, config: crawlConfig))
                discoveredPrograms.append(
                    contentsOf: parsePrograms(
                        from: xml,
                        pageURL: pageURL,
                        config: crawlConfig,
                        parseRequirements: parseRequirements,
                        schoolID: schoolID
                    )
                )
            } catch {
                continue
            }
        }

        let dedupedCourses = deduplicateCourses(discoveredCourses)
        let dedupedPrograms = deduplicatePrograms(discoveredPrograms)
        let signature = computeSignature(from: signatureMaterial, schoolID: schoolID)

        let preferred = CatalogLayoutProfileRegistry.preferredProfileID(forSchoolID: schoolID)
        return CrawlOutput(
            courses: dedupedCourses,
            programs: dedupedPrograms,
            sourceSignature: signature,
            dominantLayoutProfileID: preferred?.rawValue ?? CourseLeafLayoutProfileID.profileDefault.rawValue,
            layoutConfidence: preferred == nil ? 0.65 : 0.8
        )
    }

    static func normalizeBaseURL(_ rawURL: String) -> URL? {
        guard var components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url
    }

    static func sitemapPageURLs(baseURL: URL) async throws -> [URL] {
        try await CourseLeafSitemapCache.pageURLs(baseURL: baseURL)
    }

    private static func fetchXML(from url: URL) async throws -> String {
        try await CourseLeafXMLClient.fetchXML(from: url)
    }

    private static func parseCourses(from xml: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        guard shouldParseCourses(pageURL: pageURL, config: config) else { return [] }
        guard xml.contains("<courseleaf") else { return [] }

        var courses: [CatalogCourse] = []
        for html in extractCDATAHTMLFragments(from: xml, patterns: config.cdataHTMLPatterns) {
            courses.append(contentsOf: CourseLeafEntityExtractor.extractCoursesFromHTML(html, pageURL: pageURL, config: config))
        }

        if courses.isEmpty {
            courses.append(contentsOf: CourseLeafEntityExtractor.extractCoursesLegacyFallback(
                from: xml,
                pageURL: pageURL,
                config: config
            ))
        }
        return courses
    }

    private static func extractCDATAHTMLFragments(from xml: String, patterns: [String]) -> [String] {
        let patternSource = patterns.first ?? "<!\\[CDATA\\[(.*?)\\]\\]>"
        let pattern = try? NSRegularExpression(pattern: patternSource, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let pattern else { return [] }
        return pattern.matches(in: xml, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            let html = String(xml[range])
            guard html.contains("courseblock") || html.contains("courseblocktitle") else { return nil }
            return html
        }
    }

    /// Test entry: parse program metadata (+ optional requirements) from fixture `index.xml`.
    static func parseProgramsForTests(
        from xml: String,
        pageURL: URL,
        schoolID: String,
        parseRequirements: Bool
    ) -> [ScrapedProgram] {
        parseProgramsForTests(
            from: xml,
            pageURL: pageURL,
            profileConfig: CatalogLayoutProfileRegistry.legacyCrawlConfig(forSchoolID: schoolID),
            schoolID: schoolID,
            parseRequirements: parseRequirements
        )
    }

    /// IR pipeline entry: program metadata uses layout profile path hints.
    static func parseProgramsForTests(
        from xml: String,
        pageURL: URL,
        profileConfig: CourseLeafProfileConfig,
        schoolID: String,
        parseRequirements: Bool
    ) -> [ScrapedProgram] {
        parsePrograms(
            from: xml,
            pageURL: pageURL,
            config: profileConfig,
            parseRequirements: parseRequirements,
            schoolID: schoolID
        )
    }

    private static func parsePrograms(
        from xml: String,
        pageURL: URL,
        config: CourseLeafProfileConfig,
        parseRequirements: Bool = false,
        schoolID: String = ""
    ) -> [ScrapedProgram] {
        guard shouldParsePrograms(pageURL: pageURL, config: config) else {
            return []
        }
        guard xml.contains("<courseleaf") else { return [] }

        let titlePattern = try? NSRegularExpression(pattern: "<title>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let title: String = {
            guard let titleMatch = titlePattern?.firstMatch(in: xml, options: [], range: nsRange),
                  let range = Range(titleMatch.range(at: 1), in: xml) else {
                return pageURL.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
            }
            return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        if CourseLeafProgramURLParser.isJunkProgramTitle(title) {
            return []
        }

        let path = pageURL.path.lowercased()
        let lower = title.lowercased()
        let type: String = {
            if path.contains("/minor") || config.minorKeywords.contains(where: { lower.contains($0) }) {
                return "Minor"
            }
            if path.contains("/major") || config.majorKeywords.contains(where: { lower.contains($0) }) {
                return "Major"
            }
            if lower.contains("minor") { return "Minor" }
            if lower.contains("bachelor") || lower.contains("b.s") || lower.contains("b.a") || lower.contains("degree") {
                return "Major"
            }
            return "Major"
        }()

        let ownership = CourseLeafProgramURLParser.ownership(from: pageURL)
        let degreeType = CourseLeafProgramURLParser.degreeTypeFromTitle(title)
        let baseName = title.isEmpty ? pageURL.lastPathComponent : title

        var requirements: [DegreeRequirement]?
        if parseRequirements {
            if let parsed = try? CourseLeafRequirementsParser.parseRequirements(
                fromXML: xml,
                programURL: pageURL,
                schoolID: schoolID,
                degreeType: degreeType,
                programName: baseName
            ), !parsed.isEmpty {
                requirements = parsed
            }
        }

        var programs: [ScrapedProgram] = [
            ScrapedProgram(
                name: baseName,
                type: type,
                url: pageURL.absoluteString,
                department: ownership.department,
                college: ownership.college,
                degreeType: degreeType,
                requirements: requirements
            )
        ]

        if parseRequirements {
            let fragments = CourseLeafRequirementsParser.extractRequirementFragments(
                from: xml,
                schoolID: schoolID,
                programURL: pageURL,
                degreeType: degreeType
            )
            for variant in fragments.trackVariants {
                guard !variant.html.isEmpty else { continue }
                let wrapped = CourseLeafRequirementsParser.wrapHTMLFragment(variant.html)
                let rawTrack = (try? {
                    let doc = try SwiftSoup.parse(wrapped, pageURL.absoluteString)
                    return try CourseLeafCourselistHTMLParser.parse(doc: doc, logger: DebugLogger.shared)
                }()) ?? nil
                let trackRequirements = CourseLeafRequirementsParser.stampProgramMetadata(
                    rawTrack ?? [],
                    programName: "\(baseName) (\(variant.displayName))",
                    degreeType: degreeType,
                    programURL: pageURL
                )
                guard !trackRequirements.isEmpty else { continue }
                let trackURL = "\(pageURL.absoluteString)#track=\(variant.trackID)"
                let parentKey = pageURL.absoluteString
                programs.append(
                    ScrapedProgram(
                        name: "\(baseName) (\(variant.displayName))",
                        type: type,
                        url: trackURL,
                        department: ownership.department,
                        college: ownership.college,
                        degreeType: degreeType,
                        requirements: trackRequirements,
                        trackVariant: variant.trackID,
                        parentProgramURL: parentKey
                    )
                )
            }
        }

        return programs
    }

    private static func deduplicateCourses(_ courses: [CatalogCourse]) -> [CatalogCourse] {
        var bestByCode: [String: CatalogCourse] = [:]
        for course in courses {
            let key = course.courseCode.uppercased()
            if let existing = bestByCode[key] {
                bestByCode[key] = preferredCourse(existing, course)
            } else {
                bestByCode[key] = course
            }
        }
        return bestByCode.values.sorted { $0.courseCode < $1.courseCode }
    }

    private static func preferredCourse(_ lhs: CatalogCourse, _ rhs: CatalogCourse) -> CatalogCourse {
        func score(_ course: CatalogCourse) -> Int {
            var value = 0
            if course.credits > 0 { value += 4 }
            if course.description != nil { value += 2 }
            if course.title.caseInsensitiveCompare(course.courseCode) != .orderedSame { value += 3 }
            return value
        }
        return score(rhs) > score(lhs) ? rhs : lhs
    }

    private static func deduplicatePrograms(_ programs: [ScrapedProgram]) -> [ScrapedProgram] {
        var seen = Set<String>()
        var output: [ScrapedProgram] = []
        output.reserveCapacity(programs.count)
        for program in programs {
            let key = "\(program.name.lowercased())|\(program.url.lowercased())"
            if seen.insert(key).inserted {
                output.append(program)
            }
        }
        return output
    }

    private static func computeSignature(from inputs: [String], schoolID: String) -> String {
        let payload = ([schoolID] + inputs.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func shouldParseCourses(pageURL: URL, config: CourseLeafProfileConfig) -> Bool {
        let path = pageURL.path.lowercased()
        return config.coursePagePathHints.contains(where: { path.contains($0) })
    }

    private static func shouldParsePrograms(pageURL: URL, config: CourseLeafProfileConfig) -> Bool {
        let path = pageURL.path.lowercased()
        return config.programPagePathHints.contains(where: { path.contains($0) })
    }

    static func normalizedIndexURL(from pageURL: URL) -> URL {
        CourseLeafXMLClient.normalizedIndexURL(from: pageURL)
    }
}
