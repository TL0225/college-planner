// CourseLeafLayoutProfiles.swift
// Feature: Catalog
// Purpose: CourseLeaf layout profiles — entity extraction from CatalogDocumentIR.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

enum CourseLeafLayoutProfileID: String, Sendable, CaseIterable {
    case profileA = "profileA"
    case profileB = "profileB"
    case profileC = "profileC"
    case profileDefault = "profileDefault"

    static func resolve(_ raw: String) -> CourseLeafLayoutProfileID {
        CourseLeafLayoutProfileID(rawValue: raw) ?? .profileDefault
    }

    func extractEntities(
        from ir: CatalogDocumentIR,
        pageURL: URL,
        config: CourseLeafProfileConfig,
        xml: String
    ) -> (courses: [CatalogCourse], programs: [ScrapedProgram]) {
        let courseBlocks = ir.nodes.filter { $0.kind == .courseBlock }
        var courses: [CatalogCourse] = []

        switch self {
        case .profileA:
            for node in courseBlocks where node.elementSignature == "div.courseblock" {
                guard let html = node.text else { continue }
                courses.append(contentsOf: CourseLeafEntityExtractor.extractNYUCoursesFromHTML(html, pageURL: pageURL, config: config))
            }
        case .profileB:
            for node in courseBlocks where node.elementSignature == "div.courseblock" {
                guard let html = node.text else { continue }
                courses.append(contentsOf: CourseLeafEntityExtractor.extractFordhamCoursesFromHTML(html, pageURL: pageURL, config: config))
            }
        case .profileC:
            for node in courseBlocks where node.elementSignature == "dl.courseblock" {
                guard let html = node.text else { continue }
                courses.append(contentsOf: CourseLeafEntityExtractor.extractCMUCoursesFromHTML(html, pageURL: pageURL, config: config))
            }
        case .profileDefault:
            for node in courseBlocks {
                guard let html = node.text else { continue }
                courses.append(contentsOf: CourseLeafEntityExtractor.extractCoursesFromHTML(html, pageURL: pageURL, config: config))
            }
            if courses.isEmpty {
                courses = CourseLeafEntityExtractor.extractCoursesLegacyFallback(from: xml, pageURL: pageURL, config: config)
            }
        }

        return (courses: courses, programs: [])
    }
}
