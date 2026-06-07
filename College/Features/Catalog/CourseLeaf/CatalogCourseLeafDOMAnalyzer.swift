// CatalogCourseLeafDOMAnalyzer.swift
// Feature: Catalog
// Purpose: CourseLeaf index.xml / CDATA HTML → CatalogDocumentIR node tree + DOM features.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

struct CatalogDOMFeatures: Sendable, Equatable {
    var detailCodeCount: Int = 0
    var courseblocktitleCount: Int = 0
    var divCourseblockCount: Int = 0
    var dlCourseblockCount: Int = 0
    var scCourselistCount: Int = 0
    var headingCount: Int = 0
    var linkListCount: Int = 0
    var courseblockextraCount: Int = 0
    var detailTitleCount: Int = 0
}

struct CatalogCourseLeafDOMAnalysis: Sendable {
    let nodes: [CatalogDocumentNode]
    let domFeatures: CatalogDOMFeatures
}

enum CatalogCourseLeafDOMAnalyzer {
    static func analyze(
        xml: String,
        pageURL: URL,
        schoolID: String,
        catalogVersionID: String
    ) -> CatalogCourseLeafDOMAnalysis {
        let sectionConfig = CourseLeafRequirementSectionConfig.forSchoolID(schoolID)
        var nodes: [CatalogDocumentNode] = []
        var features = CatalogDOMFeatures()

        let sections = CourseLeafRequirementsParser.parseNamedSections(from: xml)
        if sections.isEmpty, xml.contains("courseblock") || xml.contains("sc_courselist") {
            let sectionID = UUID()
            let label: CatalogSectionLabel = pageURL.path.lowercased().contains("/course") ? .courses : .general
            nodes.append(
                CatalogDocumentNode(
                    id: sectionID,
                    parentID: nil,
                    depth: 0,
                    kind: .section,
                    text: nil,
                    sourceURL: pageURL.absoluteString,
                    elementSignature: "html.fragment",
                    sectionLabel: label
                )
            )
            ingestHTML(
                xml,
                parentID: sectionID,
                depth: 1,
                pageURL: pageURL,
                nodes: &nodes,
                features: &features
            )
        } else {
            for section in sections {
                let sectionLabel = sectionLabel(for: section.elementName, sectionConfig: sectionConfig)
                let sectionID = UUID()
                nodes.append(
                    CatalogDocumentNode(
                        id: sectionID,
                        parentID: nil,
                        depth: 0,
                        kind: .section,
                        text: section.elementName,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: section.elementName,
                        sectionLabel: sectionLabel
                    )
                )
                ingestHTML(
                    section.html,
                    parentID: sectionID,
                    depth: 1,
                    pageURL: pageURL,
                    nodes: &nodes,
                    features: &features
                )
            }
        }

        return CatalogCourseLeafDOMAnalysis(nodes: nodes, domFeatures: features)
    }

    static func buildIR(
        schoolID: String,
        catalogVersionID: String,
        analysis: CatalogCourseLeafDOMAnalysis,
        layoutProfileID: String,
        layoutConfidence: CatalogExtractionConfidence
    ) -> CatalogDocumentIR {
        CatalogDocumentIR.build(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            engine: "courseleaf",
            layoutProfileID: layoutProfileID,
            nodes: analysis.nodes,
            layoutConfidence: layoutConfidence
        )
    }

    private static func sectionLabel(for elementName: String, sectionConfig: CourseLeafRequirementSectionConfig) -> CatalogSectionLabel {
        let lower = elementName.lowercased()
        if sectionConfig.isPrimaryRequirementSection(elementName: lower) || lower.contains("requirement") {
            return .requirements
        }
        if lower.contains("coursestext") || lower.contains("course") {
            return .courses
        }
        if lower.contains("curriculum") || lower.contains("program") {
            return .programs
        }
        if lower.contains("policy") {
            return .policies
        }
        return .general
    }

    private static func ingestHTML(
        _ html: String,
        parentID: UUID,
        depth: Int,
        pageURL: URL,
        nodes: inout [CatalogDocumentNode],
        features: inout CatalogDOMFeatures
    ) {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return }
        accumulateFeatures(from: doc, features: &features)

        if let blocks = try? doc.select("div.courseblock") {
            for block in blocks.array() {
                let outer = (try? block.outerHtml()) ?? ""
                nodes.append(
                    CatalogDocumentNode(
                        parentID: parentID,
                        depth: depth,
                        kind: .courseBlock,
                        text: outer,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: "div.courseblock"
                    )
                )
            }
        }

        if let blocks = try? doc.select("dl.courseblock") {
            for block in blocks.array() {
                let outer = (try? block.outerHtml()) ?? ""
                nodes.append(
                    CatalogDocumentNode(
                        parentID: parentID,
                        depth: depth,
                        kind: .courseBlock,
                        text: outer,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: "dl.courseblock"
                    )
                )
            }
        }

        if let tables = try? doc.select("table.sc_courselist") {
            for table in tables.array() {
                let outer = (try? table.outerHtml()) ?? ""
                nodes.append(
                    CatalogDocumentNode(
                        parentID: parentID,
                        depth: depth,
                        kind: .requirementTable,
                        text: outer,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: "table.sc_courselist"
                    )
                )
            }
        }

        if let headings = try? doc.select("h1, h2, h3, h4") {
            for heading in headings.array() {
                let tag = heading.tagName().lowercased()
                let text = CourseLeafEntityExtractor.normalizedWhitespace((try? heading.text()) ?? "")
                guard !text.isEmpty else { continue }
                nodes.append(
                    CatalogDocumentNode(
                        parentID: parentID,
                        depth: depth,
                        kind: .heading,
                        text: text,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: tag
                    )
                )
            }
        }

        if let lists = try? doc.select("ul.linklist, div.linklist ul, ul") {
            for list in lists.array() {
                let anchors = (try? list.select("a[href]")) ?? Elements()
                guard anchors.size() >= 2 else { continue }
                let outer = (try? list.outerHtml()) ?? ""
                nodes.append(
                    CatalogDocumentNode(
                        parentID: parentID,
                        depth: depth,
                        kind: .linkList,
                        text: outer,
                        sourceURL: pageURL.absoluteString,
                        elementSignature: "ul.linklist"
                    )
                )
            }
        }
    }

    private static func accumulateFeatures(from doc: Document, features: inout CatalogDOMFeatures) {
        features.detailCodeCount += countElements(doc, ".detail-code")
        features.detailTitleCount += countElements(doc, ".detail-title")
        features.courseblocktitleCount += countElements(doc, "p.courseblocktitle, .courseblocktitle")
        features.divCourseblockCount += countElements(doc, "div.courseblock")
        features.dlCourseblockCount += countElements(doc, "dl.courseblock")
        features.scCourselistCount += countElements(doc, "table.sc_courselist")
        features.headingCount += countElements(doc, "h1, h2, h3, h4")
        features.courseblockextraCount += countElements(doc, ".courseblockextra")
        features.linkListCount += countElements(doc, "ul.linklist, div.linklist ul")
    }

    private static func countElements(_ doc: Document, _ selector: String) -> Int {
        (try? doc.select(selector).size()) ?? 0
    }
}
