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
                return buildSectionsFromStarts(bestStarts: bestStarts, pageCount: pageCount)
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

        guard firstHits.hasAnyRealSection else { return [] }
        return buildSectionsFromSampleHits(firstHits: firstHits, pageCount: pageCount)
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

    private static func classifyKindFromTitle(_ title: String) -> (kind: CatalogPDFSectionKind, confidence: Float)? {
        let t = title.lowercased()
        let score = { (k: CatalogPDFSectionKind, v: Float) -> (CatalogPDFSectionKind, Float) in (k, v) }

        if t.contains("course description") || t.contains("course descriptions") || t.contains("courses of instruction") {
            return score(.courseDescriptions, 0.9)
        }
        if t.contains("programs of study") || t.contains("programs and majors") || t.contains("undergraduate programs") {
            return score(.programs, 0.88)
        }
        if (t.contains("major") || t.contains("majors")) && !t.contains("requirement") && !t.contains("policy") {
            return score(.programs, 0.82)
        }
        if t.contains("program") && !t.contains("requirement") && !t.contains("policy") && !t.contains("procedure") {
            return score(.programs, 0.78)
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
