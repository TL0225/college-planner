// ModernCampusIRCourseExtractor.swift
// Feature: Catalog
// Purpose: Extract CatalogCourse stubs from Modern Campus Document IR link nodes.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum ModernCampusIRCourseExtractor {
    static func courses(from ir: CatalogDocumentIR) -> [CatalogCourse] {
        var byCode: [String: CatalogCourse] = [:]
        for node in ir.nodes {
            guard let url = node.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  url.localizedCaseInsensitiveContains("preview_course") else { continue }
            guard let parsed = parseCourse(node: node, detailURL: url) else { continue }
            let code = CatalogImportTransforms.normalizeCourseCode(parsed.courseCode)
            guard !code.isEmpty else { continue }
            if byCode[code] == nil {
                byCode[code] = parsed
            }
        }
        return Array(byCode.values).sorted { $0.courseCode < $1.courseCode }
    }

    private static func parseCourse(node: CatalogDocumentNode, detailURL: String) -> CatalogCourse? {
        let label = (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let (code, title) = splitCourseLabel(label)
        let resolvedCode = code.isEmpty ? codeFromURL(detailURL) : code
        guard !resolvedCode.isEmpty else { return nil }
        let resolvedTitle = title.isEmpty ? resolvedCode : title
        let coid = coidFromURL(detailURL)
        let course = CatalogCourse(
            courseCode: resolvedCode,
            title: resolvedTitle,
            credits: 0,
            department: nil,
            catalogCoid: coid,
            previewDetailURL: detailURL
        )
        return CatalogExternalReferenceBuilder.enriching(course, engine: "moderncampus")
    }

    private static func splitCourseLabel(_ label: String) -> (code: String, title: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }
        if let range = trimmed.range(of: #"^[A-Z]{2,8}\s*\d{1,4}[A-Z]?"#, options: .regularExpression) {
            let code = String(trimmed[range]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let title = trimmed[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:\t"))
            return (code, title)
        }
        return ("", trimmed)
    }

    private static func codeFromURL(_ url: String) -> String {
        guard let components = URLComponents(string: url),
              let coid = components.queryItems?.first(where: { $0.name == "coid" })?.value,
              !coid.isEmpty else { return "" }
        return "MC-\(coid)"
    }

    private static func coidFromURL(_ url: String) -> String? {
        guard let components = URLComponents(string: url),
              let coid = components.queryItems?.first(where: { $0.name == "coid" })?.value,
              !coid.isEmpty else { return nil }
        return coid
    }
}
