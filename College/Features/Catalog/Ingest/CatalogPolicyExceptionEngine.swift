// CatalogPolicyExceptionEngine.swift
// Feature: Catalog
// Purpose: Typed evaluable policy exceptions separate from requirements (P28).

import Foundation

enum CatalogPolicyExceptionKind: String, Codable, Sendable {
    case waiver
    case substitution
    case residency
    case gpaMinimum
    case creditCap
    case other
}

struct CatalogPolicyException: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let kind: CatalogPolicyExceptionKind
    let title: String
    let bodyText: String
    let catalogScope: String
    let bindingProgram: String?
    let sourceURL: String?
}

enum CatalogPolicyExceptionEngine {
    static func extract(from policyDocuments: [(navTitle: String, bodyText: String, catalogScope: String, sourceURL: String)]) -> [CatalogPolicyException] {
        policyDocuments.compactMap { doc in
            let kind = classify(navTitle: doc.navTitle, body: doc.bodyText)
            guard kind != .other || doc.bodyText.count < 4000 else { return nil }
            return CatalogPolicyException(
                id: UUID(),
                kind: kind,
                title: doc.navTitle,
                bodyText: doc.bodyText,
                catalogScope: doc.catalogScope,
                bindingProgram: extractProgramBinding(from: doc.bodyText),
                sourceURL: doc.sourceURL
            )
        }
    }

    static func extract(from rows: [(sourceURL: String, navTitle: String, sectionHeading: String?, bodyText: String, catalogScope: String, contentHash: String, binding: String?)]) -> [CatalogPolicyException] {
        rows.map { row in
            CatalogPolicyException(
                id: UUID(),
                kind: classify(navTitle: row.navTitle, body: row.bodyText),
                title: row.sectionHeading ?? row.navTitle,
                bodyText: row.bodyText,
                catalogScope: row.catalogScope,
                bindingProgram: row.binding,
                sourceURL: row.sourceURL
            )
        }
    }

    private static func classify(navTitle: String, body: String) -> CatalogPolicyExceptionKind {
        let haystack = (navTitle + " " + body).lowercased()
        if haystack.contains("waiver") { return .waiver }
        if haystack.contains("substitut") { return .substitution }
        if haystack.contains("residency") { return .residency }
        if haystack.contains("gpa") || haystack.contains("grade point") { return .gpaMinimum }
        if haystack.contains("credit cap") || haystack.contains("maximum credits") { return .creditCap }
        return .other
    }

    private static func extractProgramBinding(from body: String) -> String? {
        guard let match = body.range(of: #"(?i)program[:\s]+([A-Za-z][A-Za-z\s&-]{2,60})"#, options: .regularExpression) else {
            return nil
        }
        return String(body[match]).components(separatedBy: ":").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
