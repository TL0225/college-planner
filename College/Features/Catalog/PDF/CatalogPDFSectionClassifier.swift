// CatalogPDFSectionClassifier.swift
// Feature: Catalog
// Purpose: Catalog module — Input.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import PDFKit

/// Outline-driven page-range sections (courses, programs, requirements, policies).
enum CatalogPDFSectionClassifier {
    struct Input {
        let document: PDFDocument
    }

    static func classify(input: Input) -> [CatalogPDFDocumentSection] {
        let doc = input.document
        let pageCount = doc.pageCount

        if let outline = doc.outlineRoot, pageCount > 0 {
            let bestStarts = collectBestStartsFromOutline(outlineRoot: outline, document: doc)
            if bestStarts.hasAnyRealSection {
                return expandCourseSectionByDescribedDensity(
                    document: doc,
                    sections: augmentWithDensityInference(document: doc, sections: buildSectionsFromStarts(bestStarts: bestStarts, pageCount: pageCount))
                )
            }
        }

        let pageStride = max(5, pageCount / 80)
        var firstHits: [CatalogPDFSectionKind: (page: Int, confidence: Float)] = [:]

        guard pageCount > 0 else { return [] }

        for idx in stride(from: 0, to: pageCount, by: pageStride) {
            guard let page = doc.page(at: idx) else { continue }
            let text = (page.string ?? "").lowercased()
            if let match = classifyKindFromText(text) {
                firstHits.updateMaxConfidence(for: match.kind, page: idx, confidence: match.confidence)
            }
        }

        guard firstHits.hasAnyRealSection else {
            return densityOnlySections(document: doc, pageCount: pageCount)
        }
        return expandCourseSectionByDescribedDensity(
            document: doc,
            sections: augmentWithDensityInference(
                document: doc,
                sections: buildSectionsFromSampleHits(firstHits: firstHits, pageCount: pageCount)
            )
        )
    }

    /// Extends the course-descriptions section to cover the full contiguous run of
    /// pages with sustained *described-header* density. Outline neighbor boundaries
    /// often truncate the course body (a spurious "programs" bookmark mid-catalog, or
    /// a department that starts before the bookmarked page); this recovers those head
    /// and tail courses. The section is only ever **extended**, never shrunk, so
    /// correctly-bounded catalogs (e.g. Fordham) are unaffected. Other sections that
    /// become enclosed by the expanded range are clipped or dropped to keep sections
    /// non-overlapping.
    private static func expandCourseSectionByDescribedDensity(
        document: PDFDocument,
        sections: [CatalogPDFDocumentSection]
    ) -> [CatalogPDFDocumentSection] {
        guard let courseIdx = sections.firstIndex(where: { $0.kind == .courseDescriptions }) else {
            return sections
        }
        let course = sections[courseIdx]
        let density = CatalogPDFCourseFormatDetector.describedHeaderDensityByPage(document: document)
        let pageCount = density.count
        guard pageCount > 0 else { return sections }

        let minPerPage = 2
        let maxGap = 12

        let clampedEnd = min(course.endPage, pageCount - 1)
        guard course.startPage <= clampedEnd else { return sections }
        let seed = (course.startPage...clampedEnd).first(where: { density[$0] >= minPerPage }) ?? course.startPage

        var start = course.startPage
        var gap = 0
        var page = seed - 1
        while page >= 0 {
            if density[page] > 0 { start = min(start, page) }
            if density[page] >= minPerPage { gap = 0 }
            else { gap += 1; if gap > maxGap { break } }
            page -= 1
        }

        var end = course.endPage
        gap = 0
        page = seed + 1
        while page < pageCount {
            if density[page] > 0 { end = max(end, page) }
            if density[page] >= minPerPage { gap = 0 }
            else { gap += 1; if gap > maxGap { break } }
            page += 1
        }

        // Union only — never shrink a correctly-detected section.
        start = min(start, course.startPage)
        end = max(end, course.endPage)
        guard start != course.startPage || end != course.endPage else { return sections }

        var out = sections
        out[courseIdx] = CatalogPDFDocumentSection(
            kind: .courseDescriptions,
            confidence: course.confidence,
            startPage: start,
            endPage: end
        )

        out = out.compactMap { section in
            guard section.kind != .courseDescriptions else { return section }
            // Fully enclosed by the expanded course range -> drop.
            if section.startPage >= start && section.endPage <= end { return nil }
            // Tail overlaps the new course start -> clip its end.
            if section.startPage < start && section.endPage >= start {
                return CatalogPDFDocumentSection(
                    kind: section.kind, confidence: section.confidence,
                    startPage: section.startPage, endPage: start - 1
                )
            }
            // Head overlaps the new course end -> clip its start.
            if section.startPage <= end && section.endPage > end {
                return CatalogPDFDocumentSection(
                    kind: section.kind, confidence: section.confidence,
                    startPage: end + 1, endPage: section.endPage
                )
            }
            return section
        }

        out.append(contentsOf: supplementalStudentTaughtCourseSections(
            document: document,
            density: density,
            excluding: start...end
        ))

        return out.sorted { $0.startPage < $1.startPage }
    }

    /// Some catalogs include small, standalone student-taught course tables outside
    /// the main department course-description section. Treat only explicit
    /// "Student-Taught Courses" islands as supplemental course sections so broader
    /// requirement/curriculum tables do not get parsed as courses.
    private static func supplementalStudentTaughtCourseSections(
        document: PDFDocument,
        density: [Int],
        excluding courseRange: ClosedRange<Int>
    ) -> [CatalogPDFDocumentSection] {
        var out: [CatalogPDFDocumentSection] = []
        var consumed: Set<Int> = []

        for pageIndex in 0..<document.pageCount {
            guard !courseRange.contains(pageIndex), !consumed.contains(pageIndex) else { continue }
            let text = (document.page(at: pageIndex)?.string ?? "").lowercased()
            guard text.contains("student-taught courses") || text.contains("student taught courses") else { continue }
            guard pageIndex < density.count, density[pageIndex] > 0 else { continue }

            var end = pageIndex
            var next = pageIndex + 1
            while next < density.count, density[next] > 0, next <= pageIndex + 3 {
                end = next
                next += 1
            }
            for idx in pageIndex...end { consumed.insert(idx) }
            out.append(CatalogPDFDocumentSection(
                kind: .courseDescriptions,
                confidence: 0.72,
                startPage: pageIndex,
                endPage: end
            ))
        }

        return out
    }

    /// When outline/text heuristics miss the course catalog body, infer it from sustained code density.
    private static func augmentWithDensityInference(
        document: PDFDocument,
        sections: [CatalogPDFDocumentSection]
    ) -> [CatalogPDFDocumentSection] {
        let programsStart = sections.first(where: { $0.kind == .programs })?.startPage
        guard let inferred = CatalogPDFCourseFormatDetector.inferCourseDescriptionPageRange(
            document: document,
            programsStartPage: programsStart
        ) else {
            return sections
        }

        let inferredSection = CatalogPDFDocumentSection(
            kind: .courseDescriptions,
            confidence: 0.85,
            startPage: inferred.lowerBound,
            endPage: max(inferred.lowerBound, inferred.upperBound - 1)
        )

        if let existingIdx = sections.firstIndex(where: { $0.kind == .courseDescriptions }) {
            let existing = sections[existingIdx]
            // Replace TOC false positives or sections that start well before the real course body.
            if inferred.lowerBound > existing.startPage + 40 || existing.startPage < 50 {
                var out = sections
                out[existingIdx] = inferredSection
                return out.sorted { $0.startPage < $1.startPage }
            }
            return sections
        }

        var out = sections
        out.append(inferredSection)
        out.sort { $0.startPage < $1.startPage }
        return out
    }

    private static func densityOnlySections(document: PDFDocument, pageCount: Int) -> [CatalogPDFDocumentSection] {
        guard let inferred = CatalogPDFCourseFormatDetector.inferCourseDescriptionPageRange(document: document) else {
            return []
        }
        return [
            CatalogPDFDocumentSection(
                kind: .courseDescriptions,
                confidence: 0.68,
                startPage: inferred.lowerBound,
                endPage: max(inferred.lowerBound, inferred.upperBound - 1)
            )
        ]
    }

    static func sectionKind(forPage pageIndex: Int, sections: [CatalogPDFDocumentSection]) -> CatalogPDFSectionKind? {
        for section in sections where pageIndex >= section.startPage && pageIndex <= section.endPage {
            if section.kind != .ignored { return section.kind }
        }
        return nil
    }

    // MARK: - Outline

    private struct BestStarts {
        var courseDescriptions: (page: Int, confidence: Float)?
        var programs: (page: Int, confidence: Float)?
        var degreeRequirements: (page: Int, confidence: Float)?
        var policies: (page: Int, confidence: Float)?

        var hasAnyRealSection: Bool {
            courseDescriptions != nil || programs != nil || degreeRequirements != nil || policies != nil
        }
    }

    private static func collectBestStartsFromOutline(outlineRoot: PDFOutline, document: PDFDocument) -> BestStarts {
        var best = BestStarts()

        func visit(_ node: PDFOutline) {
            let title = node.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty, let kindScore = classifyKindFromTitle(title) {
                if let destPage = node.destination?.page {
                    let pageIndex = document.index(for: destPage)
                    guard pageIndex >= 0 else { return }
                    switch kindScore.kind {
                    case .courseDescriptions:
                        best.courseDescriptions = pickHigher(best.courseDescriptions, new: (pageIndex, kindScore.confidence))
                    case .programs:
                        best.programs = pickHigher(best.programs, new: (pageIndex, kindScore.confidence))
                    case .degreeRequirements:
                        best.degreeRequirements = pickHigher(best.degreeRequirements, new: (pageIndex, kindScore.confidence))
                    case .policies:
                        best.policies = pickHigher(best.policies, new: (pageIndex, kindScore.confidence))
                    case .ignored:
                        break
                    }
                }
            }

            for idx in 0..<node.numberOfChildren {
                if let child = node.child(at: idx) {
                    visit(child)
                }
            }
        }

        for idx in 0..<outlineRoot.numberOfChildren {
            if let child = outlineRoot.child(at: idx) {
                visit(child)
            }
        }
        return best
    }

    private static func pickHigher(
        _ existing: (page: Int, confidence: Float)?,
        new: (page: Int, confidence: Float)
    ) -> (page: Int, confidence: Float) {
        guard let existing else { return new }
        if new.confidence > existing.confidence { return new }
        if abs(new.confidence - existing.confidence) < 0.001, new.page < existing.page { return new }
        return existing
    }

    static func classifyKindFromTitle(_ title: String) -> (kind: CatalogPDFSectionKind, confidence: Float)? {
        let t = title.lowercased()
        let score = { (k: CatalogPDFSectionKind, v: Float) -> (CatalogPDFSectionKind, Float) in (k, v) }

        if isNonAcademicProgramTitle(t) {
            return nil
        }

        if t.contains("course description") || t.contains("course descriptions") || t.contains("courses of instruction") {
            return score(.courseDescriptions, 0.9)
        }
        if t.contains("programs of study") || t.contains("programs and majors") || t.contains("undergraduate programs") {
            return score(.programs, 0.88)
        }
        if t.contains("academic programs") || t.contains("academic program index") || t.contains("program areas") || t.contains("pcs programs") {
            return score(.programs, 0.84)
        }
        if t.contains("degree programs") || t.contains("doctoral programs") || t.contains("master of science programs") ||
            t.contains("master of business administration programs") || t.contains("certificate") && t.contains("program") {
            return score(.programs, 0.84)
        }
        if (t.contains("major") || t.contains("majors")) && !t.contains("requirement") && !t.contains("policy") {
            return score(.programs, 0.82)
        }
        if (t.contains("minor") || t.contains("minors")) && !t.contains("requirement") && !t.contains("policy") {
            return score(.programs, 0.82)
        }
        if t.contains("degree requirement") || t.contains("curriculum") || t.contains("program requirements") {
            return score(.degreeRequirements, 0.8)
        }
        if t.contains("academic regulation") || t.contains("academic policies") || t.contains("policies and procedures") {
            return score(.policies, 0.82)
        }
        if t.contains("policy") || t.contains("grading") || t.contains("transfer credit") {
            return score(.policies, 0.75)
        }
        if t.contains("tuition") || t.contains("housing") || t.contains("calendar") || t.contains("admission") || t.contains("ferpa") {
            return score(.ignored, 0.2)
        }

        return nil
    }

    private static func isNonAcademicProgramTitle(_ title: String) -> Bool {
        let policyOrDirectoryPhrases = [
            "limits on number of majors",
            "limits on number of major",
            "study abroad finances",
            "leadership development programs",
            "student services",
            "satisfactory academic progress",
            "program handbook",
        ]
        return policyOrDirectoryPhrases.contains { title.contains($0) }
    }

    private static func classifyKindFromText(_ text: String) -> (kind: CatalogPDFSectionKind, confidence: Float)? {
        let t = text.lowercased()
        if t.contains("course descriptions") || (t.contains("courses of instruction") && t.contains("credit")) {
            return (.courseDescriptions, 0.55)
        }
        if t.contains("programs of study") || t.contains("undergraduate programs") {
            return (.programs, 0.52)
        }
        if (t.contains("majors") || t.contains("minors")) && !t.contains("policy") && !t.contains("tuition") {
            return (.programs, 0.48)
        }
        if t.contains("degree requirements") || t.contains("curriculum requirements") {
            return (.degreeRequirements, 0.5)
        }
        if t.contains("academic policy") || t.contains("academic regulations") {
            return (.policies, 0.45)
        }
        return nil
    }

    private static func buildSectionsFromStarts(bestStarts: BestStarts, pageCount: Int) -> [CatalogPDFDocumentSection] {
        var items: [(kind: CatalogPDFSectionKind, start: Int, confidence: Float)] = []
        if let s = bestStarts.courseDescriptions { items.append((.courseDescriptions, s.page, s.confidence)) }
        if let s = bestStarts.programs { items.append((.programs, s.page, s.confidence)) }
        if let s = bestStarts.degreeRequirements { items.append((.degreeRequirements, s.page, s.confidence)) }
        if let s = bestStarts.policies { items.append((.policies, s.page, s.confidence)) }

        items.sort { $0.start < $1.start }
        guard !items.isEmpty else { return [] }

        var out: [CatalogPDFDocumentSection] = []
        out.reserveCapacity(items.count)

        for i in 0..<items.count {
            let start = max(0, min(items[i].start, pageCount - 1))
            let end: Int = i + 1 < items.count
                ? max(start, min(items[i + 1].start - 1, pageCount - 1))
                : pageCount - 1

            out.append(
                CatalogPDFDocumentSection(
                    kind: items[i].kind,
                    confidence: items[i].confidence,
                    startPage: start,
                    endPage: end
                )
            )
        }

        return out
    }

    private static func buildSectionsFromSampleHits(
        firstHits: [CatalogPDFSectionKind: (page: Int, confidence: Float)],
        pageCount: Int
    ) -> [CatalogPDFDocumentSection] {
        var items: [(kind: CatalogPDFSectionKind, start: Int, confidence: Float)] = []
        for (k, v) in firstHits where k != .ignored {
            items.append((k, v.page, v.confidence))
        }
        items.sort { $0.start < $1.start }
        guard !items.isEmpty else { return [] }

        var out: [CatalogPDFDocumentSection] = []
        out.reserveCapacity(items.count)

        for i in 0..<items.count {
            let start = max(0, min(items[i].start, pageCount - 1))
            let end: Int = i + 1 < items.count
                ? max(start, min(items[i + 1].start - 1, pageCount - 1))
                : pageCount - 1

            out.append(
                CatalogPDFDocumentSection(
                    kind: items[i].kind,
                    confidence: items[i].confidence,
                    startPage: start,
                    endPage: end
                )
            )
        }
        return out
    }
}

private extension Dictionary where Key == CatalogPDFSectionKind, Value == (page: Int, confidence: Float) {
    var hasAnyRealSection: Bool {
        keys.contains(.courseDescriptions) || keys.contains(.programs) ||
        keys.contains(.degreeRequirements) || keys.contains(.policies)
    }

    mutating func updateMaxConfidence(for kind: CatalogPDFSectionKind, page: Int, confidence: Float) {
        guard kind != .ignored else { return }
        if let existing = self[kind] {
            if confidence > existing.confidence || (abs(confidence - existing.confidence) < 0.001 && page < existing.page) {
                self[kind] = (page: page, confidence: confidence)
            }
        } else {
            self[kind] = (page: page, confidence: confidence)
        }
    }
}
