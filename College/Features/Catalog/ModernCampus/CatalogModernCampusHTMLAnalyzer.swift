// CatalogModernCampusHTMLAnalyzer.swift
// Feature: Catalog
// Purpose: Modern Campus HTML → CatalogDocumentIR (sidebar + content headers).
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

struct ModernCampusDOMAnalysis: Sendable {
    let nodes: [CatalogDocumentNode]
    let domFeatures: ModernCampusDOMFeatures
}

enum CatalogModernCampusHTMLAnalyzer {
    /// Upper guards against pathological pages while comfortably covering real catalogs.
    /// A single Acalog program-index page routinely lists 150–300 programs (e.g. DSU ≈ 194),
    /// so the previous 64-program cap silently dropped most entries on large pages.
    private static let maxProgramAnchorsPerPage = 2_000
    private static let maxCourseAnchorsPerPage = 5_000

    static func analyze(
        html: String,
        sourceURL: URL,
        schoolID: String,
        catalogVersionID: String
    ) -> ModernCampusDOMAnalysis {
        var nodes: [CatalogDocumentNode] = []
        var features = ModernCampusDOMFeatures()
        guard let doc = try? SwiftSoup.parse(html, sourceURL.absoluteString) else {
            return ModernCampusDOMAnalysis(nodes: [], domFeatures: features)
        }

        features.blockN2TableCount = (try? doc.select("table.block_n2_links").array().count) ?? 0
        features.entityPageLinkCount = (try? doc.select("a[href*=preview_entity]").array().count) ?? 0

        let sectionID = UUID()
        let sectionLabel = sectionLabel(for: sourceURL)
        nodes.append(
            CatalogDocumentNode(
                id: sectionID,
                parentID: nil,
                depth: 0,
                kind: .section,
                text: nil,
                sourceURL: sourceURL.absoluteString,
                elementSignature: "td.block_content",
                sectionLabel: sectionLabel
            )
        )

        ingestSidebar(doc: doc, parentID: sectionID, depth: 1, sourceURL: sourceURL, nodes: &nodes, features: &features)
        ingestContentHeaders(doc: doc, parentID: sectionID, depth: 1, sourceURL: sourceURL, nodes: &nodes, features: &features)

        return ModernCampusDOMAnalysis(nodes: nodes, domFeatures: features)
    }

    static func buildIR(
        schoolID: String,
        catalogVersionID: String,
        analysis: ModernCampusDOMAnalysis,
        layoutProfileID: String,
        layoutConfidence: CatalogExtractionConfidence
    ) -> CatalogDocumentIR {
        CatalogDocumentIR.build(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: "moderncampus",
            layoutProfileID: layoutProfileID,
            nodes: analysis.nodes,
            layoutConfidence: layoutConfidence
        )
    }

    private static func sectionLabel(for url: URL) -> CatalogSectionLabel {
        let path = url.absoluteString.lowercased()
        if path.contains("preview_program") { return .programs }
        if path.contains("preview_course") { return .courses }
        if ModernCampusCatalogDiscoverer.classifyPageKind(url: path) == .policy { return .policies }
        return .general
    }

    private static func ingestSidebar(
        doc: Document,
        parentID: UUID,
        depth: Int,
        sourceURL: URL,
        nodes: inout [CatalogDocumentNode],
        features: inout ModernCampusDOMFeatures
    ) {
        let sidebarAnchors = (try? doc.select("div.n2_links a[href], .block_n2_links a[href*='navoid='], a.navbar[href*='navoid=']").array()) ?? []
        guard !sidebarAnchors.isEmpty else { return }

        features.n2LinksCount = sidebarAnchors.count
        let listID = UUID()
        nodes.append(
            CatalogDocumentNode(
                id: listID,
                parentID: parentID,
                depth: depth,
                kind: .linkList,
                text: "sidebar.navigation",
                sourceURL: sourceURL.absoluteString,
                elementSignature: "div.n2_links",
                sectionLabel: .general
            )
        )

        for anchor in sidebarAnchors {
            let label = ((try? anchor.text()) ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let href = ((try? anchor.attr("abs:href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !href.isEmpty else { continue }
            nodes.append(
                CatalogDocumentNode(
                    parentID: listID,
                    depth: depth + 1,
                    kind: .linkList,
                    text: label,
                    sourceURL: href,
                    elementSignature: "div.n2_links>a",
                    sectionLabel: sidebarLinkSectionLabel(label: label)
                )
            )
        }
    }

    private static func ingestContentHeaders(
        doc: Document,
        parentID: UUID,
        depth: Int,
        sourceURL: URL,
        nodes: inout [CatalogDocumentNode],
        features: inout ModernCampusDOMFeatures
    ) {
        let content = (try? doc.select("td.block_content, div.block_content, table.table_default").first())
            ?? doc.body()
            ?? doc
        let headers = (try? content.select("h1, h2, h3, h4").array()) ?? []
        features.contentHeadingCount = headers.count
        for header in headers {
            let text = ((try? header.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let tag = header.tagName().lowercased()
            nodes.append(
                CatalogDocumentNode(
                    parentID: parentID,
                    depth: depth,
                    kind: .heading,
                    text: text,
                    sourceURL: sourceURL.absoluteString,
                    elementSignature: "\(tag).block_content",
                    sectionLabel: headingSectionLabel(text: text)
                )
            )
        }

        let courseAnchors = (try? content.select("a[href*=preview_course], a[href*=preview_course_nopop]").array()) ?? []
        for anchor in courseAnchors.prefix(maxCourseAnchorsPerPage) {
            let label = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = ((try? anchor.attr("abs:href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            nodes.append(
                CatalogDocumentNode(
                    parentID: parentID,
                    depth: depth + 1,
                    kind: .courseBlock,
                    text: label.isEmpty ? nil : label,
                    sourceURL: href,
                    elementSignature: "a.preview_course",
                    sectionLabel: .courses
                )
            )
        }

        let programAnchors = (try? content.select("a[href*=preview_program]").array()) ?? []
        features.previewProgramLinkCount = programAnchors.count
        for anchor in programAnchors.prefix(maxProgramAnchorsPerPage) {
            let label = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = ((try? anchor.attr("abs:href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            nodes.append(
                CatalogDocumentNode(
                    parentID: parentID,
                    depth: depth + 1,
                    kind: .programBlock,
                    text: label.isEmpty ? nil : label,
                    sourceURL: href,
                    elementSignature: "a.preview_program",
                    sectionLabel: .programs
                )
            )
        }

        // Entity pages can be a first hop to program anchors on hosts like UB.
        let entityAnchors = (try? content.select("a[href*=preview_entity]").array()) ?? []
        for anchor in entityAnchors.prefix(maxProgramAnchorsPerPage) {
            let label = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = ((try? anchor.attr("abs:href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            nodes.append(
                CatalogDocumentNode(
                    parentID: parentID,
                    depth: depth + 1,
                    kind: .linkList,
                    text: label.isEmpty ? nil : label,
                    sourceURL: href,
                    elementSignature: "a.preview_entity",
                    sectionLabel: .programs
                )
            )
        }
    }

    private static func sidebarLinkSectionLabel(label: String) -> CatalogSectionLabel {
        let lower = label.lowercased()
        if lower.contains("course") { return .courses }
        if lower.contains("program") || lower.contains("major") || lower.contains("minor") { return .programs }
        if lower.contains("policy") || lower.contains("regulation") { return .policies }
        return .general
    }

    private static func headingSectionLabel(text: String) -> CatalogSectionLabel {
        let lower = text.lowercased()
        if lower.contains("requirement") { return .requirements }
        if lower.contains("course") { return .courses }
        if lower.contains("program") || lower.contains("major") || lower.contains("minor") { return .programs }
        return .general
    }
}
