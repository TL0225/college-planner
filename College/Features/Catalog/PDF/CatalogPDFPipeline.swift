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
        let engine = CatalogPDFEngine()
        let foundation = try await engine.buildFoundation(from: pdfURL)
        let healthReport = try await engine.buildHealthReport(from: pdfURL)
        let profile = CatalogPDFProfileLoader.profile(forSchoolID: options.schoolID)

        let extractor = try CatalogPDFTextExtractor(pdfURL: pdfURL)
        let ocrPolicy = CatalogParserCapability.ocrPolicy(for: options.schoolID)
        let shouldUseOCRFallback = (ocrPolicy == .always) || (ocrPolicy == .automatic && options.ocrFallback)

        let rawLines = await extractor.extractRawLines(
            ocrFallback: shouldUseOCRFallback,
            onPageProgress: onPageProgress
        )
        let textBlocks = CatalogPDFLayoutReconstructor.reconstruct(from: rawLines)
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

        var programs = CatalogPDFNormalizer.normalizePrograms(rawPrograms, schoolID: options.schoolID)

        if programs.isEmpty {
            let programsSection = foundation.sections.first(where: { $0.kind == .programs })
            if let programsSection {
                let range = pageRange(for: programsSection, pageCount: foundation.pageCount)
                let (pagesText, _) = await extractor.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
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

        var courses: [CatalogCourse] = []
        if options.includeCourses {
            courses = CatalogPDFCourseExtractor.extract(
                from: classifiedBlocks,
                minConfidence: courseThreshold
            )
            if courses.isEmpty {
                let courseSection = foundation.sections.first(where: { $0.kind == .courseDescriptions })
                let range = courseSection.map { pageRange(for: $0, pageCount: foundation.pageCount) } ?? 0..<foundation.pageCount
                let (pagesText, _) = await extractor.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
                let blob = pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n")
                courses = CatalogPDFNormalizer.normalizeCourses(
                    CatalogPDFCourseExtractor.extractCourses(fromText: blob)
                )
            } else {
                courses = CatalogPDFNormalizer.normalizeCourses(courses)
            }
        }

        let requirements = CatalogPDFRequirementExtractor.extractRequirements(from: programs)

        var policyRows: [(sourceURL: String, navTitle: String, sectionHeading: String?, bodyText: String, catalogScope: String, contentHash: String, binding: String?)] = []
        if options.includePolicies {
            policyRows = CatalogPDFPolicyExtractor.extractPolicyRows(
                from: classifiedBlocks,
                sourceURL: pdfURL.absoluteString
            )
            if policyRows.isEmpty {
                let policiesSection = foundation.sections.first(where: { $0.kind == .policies })
                let range = policiesSection.map { pageRange(for: $0, pageCount: foundation.pageCount) }
                    ?? 0..<min(15, foundation.pageCount)
                let (pagesText, _) = await extractor.extractPagesText(pageRange: range, ocrFallback: shouldUseOCRFallback)
                let blob = pagesText.keys.sorted().compactMap { pagesText[$0] }.joined(separator: "\n")
                policyRows = CatalogPDFPolicyExtractor.extractPolicyRows(
                    fromText: blob,
                    sourceURL: pdfURL.absoluteString
                )
            }
        }

        let ocrPagesUsed = await extractor.ocrPagesUsed()
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
            requirements: requirements,
            policyRows: policyRows,
            healthReport: healthReport,
            foundation: foundation,
            classificationDiagnostics: classificationDiagnostics,
            ocrPagesUsed: ocrPagesUsed,
            documentIR: documentIR
        )
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
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            lines.append(CatalogPDFLine(text: trimmed, pageIndex: pageIndex, lineIndexOnPage: idx))
        }
        return lines
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
