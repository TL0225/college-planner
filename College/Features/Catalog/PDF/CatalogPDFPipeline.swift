// CatalogPDFPipeline.swift
// Feature: Catalog
// Purpose: Catalog module — Options.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// End-to-end structure-first catalog PDF ingest: raw → layout → classify → recognize → normalize.
enum CatalogPDFPipeline {
    struct Options: Sendable {
        let schoolID: String
        var catalogVersionID: String?
        let includeCourses: Bool
        let includePolicies: Bool
        let ocrFallback: Bool
    }

    static func run(
        pdfURL: URL,
        options: Options,
        onPageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> CatalogPDFIngestOutput {
        let context = try CatalogPDFContext(pdfURL: pdfURL)
        return try await run(
            pdfURL: pdfURL,
            context: context,
            options: options,
            onPageProgress: onPageProgress
        )
    }

    static func run(
        pdfURL: URL,
        context: CatalogPDFContext,
        options: Options,
        onPageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> CatalogPDFIngestOutput {
        let foundation = await context.buildFoundation()
        let healthReport = await context.buildHealthReport()
        let profile = CatalogPDFProfileLoader.profile(forSchoolID: options.schoolID)

        let ocrPolicy = CatalogParserCapability.ocrPolicy(for: options.schoolID)
        let shouldUseOCRFallback = (ocrPolicy == .always) || (ocrPolicy == .automatic && options.ocrFallback)

        let rawLines = await context.extractRawLines(
            ocrFallback: shouldUseOCRFallback,
            onPageProgress: onPageProgress
        )
        let orderedLines = CatalogPDFLayoutIRBuilder.reorderLinesForReadingOrder(rawLines)
        let layoutBlocks = CatalogPDFLayoutIRBuilder.build(from: orderedLines)
        _ = CatalogPDFTableIRBuilder.build(from: layoutBlocks)
        let textBlocks = CatalogPDFLayoutReconstructor.reconstruct(from: orderedLines)
        let classifiedBlocks = CatalogPDFBlockClassifier.classify(
            blocks: textBlocks,
            sections: foundation.sections,
            profile: profile
        )

        let programThreshold = CatalogPDFProfileLoader.programMinConfidence(for: options.schoolID)
        let courseThreshold = CatalogPDFProfileLoader.courseMinConfidence(for: options.schoolID)

        let (rawPrograms, classificationDiagnostics) = CatalogPDFProgramExtractor.extract(
            from: classifiedBlocks,
            minConfidence: programThreshold
        )

        let outlinePrograms = await context.outlineEntries()

        // Generic department recognition + program-index/department-block extraction.
        // These are school-agnostic structural signals (outline is only one of them),
        // so programs/departments are recovered even when the PDF ships no outline.
        let departmentIndex = CatalogPDFDepartmentExtractor.build(from: rawLines)
        let indexPrograms = CatalogPDFNormalizer.normalizePrograms(
            CatalogPDFProgramIndexExtractor.extract(
                from: rawLines,
                departmentIndex: departmentIndex,
                sourceURL: pdfURL
            ),
            schoolID: options.schoolID
        )

        var programs = CatalogPDFNormalizer.normalizePrograms(
            CatalogPDFProgramExtractor.extractFromOutline(entries: outlinePrograms, sourceURL: pdfURL),
            schoolID: options.schoolID
        )
        if programs.isEmpty {
            programs = CatalogPDFNormalizer.normalizePrograms(rawPrograms, schoolID: options.schoolID)
        }

        if programs.isEmpty {
            let programsSection = foundation.sections.first(where: { $0.kind == .programs })
            if let programsSection {
                let range = pageRange(for: programsSection, pageCount: foundation.pageCount)
                let (pagesText, _) = await context.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
                let blob = pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n")
                let fallbackBlocks = CatalogPDFLayoutReconstructor.reconstruct(
                    from: linesFromPageBlob(blob, pageRange: range)
                )
                let fallbackClassified = CatalogPDFBlockClassifier.classify(
                    blocks: fallbackBlocks,
                    sections: foundation.sections,
                    profile: profile
                )
                let (fallbackPrograms, _) = CatalogPDFProgramExtractor.extract(
                    from: fallbackClassified,
                    minConfidence: programThreshold
                )
                programs = CatalogPDFNormalizer.normalizePrograms(fallbackPrograms, schoolID: options.schoolID)
            }
        }

        // Fuse outline/block programs with the generic program-index/department-block
        // programs, dedupe, and attach each program to its department.
        programs = fusePrograms(base: programs, index: indexPrograms, departmentIndex: departmentIndex)
        programs.sort {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.type.localizedCaseInsensitiveCompare($1.type) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let departments = departmentIndex.departments.map { ScrapedDepartment(name: $0.name, code: $0.code) }

        var courses: [CatalogCourse] = []
        var courseSectionText = ""
        var courseExtractionDiagnostics: CatalogPDFCourseExtractionDiagnostics?
        if options.includeCourses {
            let courseSections = foundation.sections
                .filter { $0.kind == .courseDescriptions }
                .sorted { $0.startPage < $1.startPage }
            let courseSectionTexts: [String]
            if courseSections.isEmpty {
                let (pagesText, _) = await context.extractPagesText(
                    pageRange: 0..<foundation.pageCount,
                    ocrFallback: shouldUseOCRFallback
                )
                courseSectionTexts = [pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n")]
            } else {
                var chunks: [String] = []
                chunks.reserveCapacity(courseSections.count)
                for section in courseSections {
                    let range = pageRange(for: section, pageCount: foundation.pageCount)
                    let (pagesText, _) = await context.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
                    chunks.append(pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n"))
                }
                courseSectionTexts = chunks
            }
            courseSectionText = courseSectionTexts.joined(separator: "\n")

            let parseResult = CatalogPDFCourseDescriptionParser.parseWithDiagnostics(
                sectionText: courseSectionText,
                profileHints: profile
            )
            let detection = parseResult.detection
            var usedAdaptive = false
            var usedLegacyFallback = false

            if detection.isHighConfidence, !parseResult.courses.isEmpty {
                courses = CatalogPDFNormalizer.normalizeCourses(parseResult.courses)
                usedAdaptive = true
            } else {
                usedLegacyFallback = true
                let blockCourses = CatalogPDFCourseExtractor.extract(
                    from: classifiedBlocks,
                    minConfidence: courseThreshold,
                    profile: profile
                )
                if !blockCourses.isEmpty {
                    courses = CatalogPDFNormalizer.normalizeCourses(blockCourses)
                } else {
                    courses = CatalogPDFNormalizer.normalizeCourses(
                        CatalogPDFCourseExtractor.extractCourses(fromText: courseSectionText, profile: profile)
                    )
                }
            }

            let withCredits = courses.filter { $0.credits > 0 }.count
            let withDescriptions = courses.filter { ($0.description?.isEmpty == false) }.count
            var failureReasons: [String: Int] = [:]
            for failure in parseResult.failedHeaders {
                let key = failure.split(separator: ":").first.map(String.init) ?? failure
                failureReasons[key, default: 0] += 1
            }
            if usedLegacyFallback {
                failureReasons["legacy_fallback", default: 0] += 1
            }

            courseExtractionDiagnostics = CatalogPDFCourseExtractionDiagnostics(
                detection: detection,
                usedAdaptiveParser: usedAdaptive,
                usedLegacyFallback: usedLegacyFallback,
                lowConfidence: !detection.isHighConfidence,
                coursesWithCredits: withCredits,
                coursesWithDescriptions: withDescriptions,
                failedHeaderCount: parseResult.failedHeaders.count,
                topFailureReasons: failureReasons.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)=\($0.value)" }
            )
        }

        // Document-order lines for the anchored requirement pass. We intentionally
        // keep every page: several catalogs (e.g. Brooklyn) interleave a program's
        // requirement prose with its course listings on the same pages, so excluding
        // course-description pages would drop those requirements. Course-catalog rows
        // are only captured when they fall under an open requirement/category header,
        // so the full-catalog tables do not contaminate attribution.
        // Requirement anchoring depends on true PDF document order. Column reorder and
        // table-IR append paths scramble program→block linkage (CMU unit tables regress).
        let requirementLines = rawLines
        // Invert the subject map (code -> name) into name -> code so prose course
        // mentions ("Accounting 2001") can be resolved to catalog codes ("ACCT 2001").
        var subjectNameToCode: [String: String] = [:]
        for (code, name) in departmentIndex.departmentNameBySubject {
            let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, subjectNameToCode[key] == nil else { continue }
            subjectNameToCode[key] = code
        }

        let requirements = CatalogPDFRequirementExtractor.extractRequirements(
            from: programs,
            classifiedBlocks: classifiedBlocks,
            courseCatalog: courses,
            lines: requirementLines,
            subjectNameToCode: subjectNameToCode
        )

        var policyRows: [CatalogPDFPolicyExtractor.PolicyRow] = []
        if options.includePolicies {
            let policiesSection = foundation.sections.first(where: { $0.kind == .policies })
            if let policiesSection {
                let range = pageRange(for: policiesSection, pageCount: foundation.pageCount)
                let (pagesText, _) = await context.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
                let blob = pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n")
                let policyHeadings = outlinePrograms
                    .filter { entry in (entry.pageIndex.map { range.contains($0) }) ?? false }
                    .map(\.title)
                policyRows = CatalogPDFPolicyExtractor.extractPolicyRows(
                    fromText: blob,
                    headings: policyHeadings,
                    sourceURL: pdfURL.absoluteString
                )
            }
            if policyRows.isEmpty {
                policyRows = CatalogPDFPolicyExtractor.extractPolicyRows(
                    from: classifiedBlocks,
                    sourceURL: pdfURL.absoluteString
                )
            }
        }

        let ocrPagesUsed = await context.ocrPagesUsed()
        let versionID = options.catalogVersionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.catalogVersionID!
            : options.schoolID
        let documentIR: CatalogDocumentIR? = CatalogPlatformFlags.documentIREnabled
            ? CatalogPDFToDocumentIRAdapter.buildIR(
                schoolID: options.schoolID,
                catalogVersionID: versionID,
                sourceURL: pdfURL.absoluteString,
                classifiedBlocks: classifiedBlocks,
                layoutProfileID: "pdf-\(options.schoolID)",
                layoutConfidence: 0.8
            )
            : nil
        return CatalogPDFIngestOutput(
            programs: programs,
            courses: courses,
            departments: departments,
            departmentSubjectMap: departmentIndex.departmentNameBySubject,
            requirements: requirements,
            policyRows: policyRows,
            healthReport: healthReport,
            foundation: foundation,
            classificationDiagnostics: classificationDiagnostics,
            courseExtractionDiagnostics: courseExtractionDiagnostics,
            ocrPagesUsed: ocrPagesUsed,
            documentIR: documentIR
        )
    }

    /// Merges the base programs (outline/block) with the generic index/department-block
    /// programs. Dedupes on type + normalized name, preferring the variant that carries
    /// a department or degree, and back-fills a department from the department index.
    private static func fusePrograms(
        base: [ScrapedProgram],
        index: [ScrapedProgram],
        departmentIndex: CatalogPDFDepartmentIndex
    ) -> [ScrapedProgram] {
        var byKey: [String: ScrapedProgram] = [:]
        var order: [String] = []

        func key(_ p: ScrapedProgram) -> String {
            "\(p.type.lowercased())|\(p.degreeType ?? "")|\(p.name.lowercased())"
        }

        func merge(_ incoming: ScrapedProgram) {
            let k = key(incoming)
            guard let existing = byKey[k] else {
                byKey[k] = incoming
                order.append(k)
                return
            }
            // Prefer the richer record (department/degree present).
            let merged = ScrapedProgram(
                name: existing.name,
                type: existing.type,
                url: existing.url.isEmpty ? incoming.url : existing.url,
                group: existing.group ?? incoming.group,
                department: existing.department ?? incoming.department,
                college: existing.college ?? incoming.college,
                degreeType: existing.degreeType ?? incoming.degreeType,
                requirements: existing.requirements ?? incoming.requirements
            )
            byKey[k] = merged
        }

        for program in base { merge(program) }
        for program in index { merge(program) }

        // Back-fill department by matching the program name to a known department.
        let deptNames = departmentIndex.departments.map { $0.name }
        let mergedPrograms = order.compactMap { byKey[$0] }
        let degreeBearingMajorNames = Set(
            mergedPrograms
                .filter { $0.type == "Major" && ($0.degreeType?.isEmpty == false) }
                .map { $0.name.lowercased() }
        )
        return mergedPrograms.filter { program in
            guard program.type == "Major", program.degreeType == nil else { return true }
            let normalizedName = program.name.lowercased()
            if degreeBearingMajorNames.contains(normalizedName) { return false }
            let letters = program.name.filter { $0.isLetter }
            if program.name.count <= 8, !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) { return false }
            return true
        }.map { program in
            guard program.department == nil,
                  let dept = matchedDepartment(for: program.name, departments: deptNames) else {
                return program
            }
            return ScrapedProgram(
                name: program.name,
                type: program.type,
                url: program.url,
                group: program.group,
                department: dept,
                college: program.college,
                degreeType: program.degreeType,
                requirements: program.requirements
            )
        }
    }

    /// Best-effort name match of a program to a department (exact or prefix containment).
    private static func matchedDepartment(for programName: String, departments: [String]) -> String? {
        let lowerProgram = programName.lowercased()
        if let exact = departments.first(where: { $0.lowercased() == lowerProgram }) { return exact }
        return departments.first { dept in
            let d = dept.lowercased()
            return d.count >= 5 && (lowerProgram.hasPrefix(d) || lowerProgram.contains(" \(d)"))
        }
    }

    private static func pageRange(for section: CatalogPDFDocumentSection, pageCount: Int) -> Range<Int> {
        let start = max(0, min(section.startPage, pageCount - 1))
        let upper = max(start + 1, min(section.endPage + 1, pageCount))
        return start..<upper
    }

    private static func linesFromPageBlob(_ blob: String, pageRange: Range<Int>) -> [CatalogPDFLine] {
        var lines: [CatalogPDFLine] = []
        let pageIndex = pageRange.lowerBound
        for (idx, raw) in blob.components(separatedBy: .newlines).enumerated() {
            let indent = leadingWhitespaceCount(in: raw)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(CatalogPDFLine(text: trimmed, pageIndex: pageIndex, lineIndexOnPage: idx, indentLevel: indent))
        }
        return lines
    }

    private static func leadingWhitespaceCount(in line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " || ch == "\t" { count += 1 } else { break }
        }
        return min(count / 2, 8)
    }
}

// MARK: - Backward-compatible typealiases (migration)

typealias PDFCatalogEngine = CatalogPDFEngine
typealias PDFTextExtractor = CatalogPDFTextExtractor
typealias PDFSectionClassifier = CatalogPDFSectionClassifier
typealias PDFCatalogSectionKind = CatalogPDFSectionKind
typealias PDFCatalogDocumentSection = CatalogPDFDocumentSection
typealias PDFHealthReport = CatalogPDFHealthReport
typealias PDFRequirementExtractor = CatalogPDFRequirementExtractor
typealias PDFPolicyExtractor = CatalogPDFPolicyExtractor
