// CatalogEntityIdentity.swift
// Feature: Catalog
// Purpose: Catalog module — stable entity IDs across catalog versions.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogEntityType: String, Codable, Sendable, CaseIterable {
    case program
    case course
    case requirementCategory
}

struct CatalogEntityIdentity: Codable, Sendable, Equatable, Hashable, Identifiable {
    let stableID: UUID
    let entityType: CatalogEntityType
    let catalogVersionID: String
    let displayKey: String

    var id: UUID { stableID }

    init(
        stableID: UUID = UUID(),
        entityType: CatalogEntityType,
        catalogVersionID: String,
        displayKey: String
    ) {
        self.stableID = stableID
        self.entityType = entityType
        self.catalogVersionID = catalogVersionID
        self.displayKey = displayKey
    }
}

enum CatalogEntityIdentityMatcher {
    private static let programURLMatchThreshold = 0.82
    private static let programTitleMatchThreshold = 0.88

    static func displayKeyForProgram(url: String, name: String, type: String) -> String {
        let path = normalizedProgramURLPath(url)
        let title = CatalogImportTransforms.normalize(name).lowercased()
        let programType = CatalogImportTransforms.normalize(type).lowercased()
        if path.isEmpty {
            return "\(programType)|\(title)"
        }
        return "\(path)|\(programType)"
    }

    static func displayKeyForCourse(courseCode: String) -> String {
        CatalogImportTransforms.normalizeCourseCode(courseCode)
    }

    static func displayKeyForRequirementCategory(programURL: String, categoryLabel: String) -> String {
        let path = normalizedProgramURLPath(programURL)
        let label = CatalogImportTransforms.normalize(categoryLabel).lowercased()
        return "\(path)#\(label)"
    }

    static func matchProgram(
        url: String,
        name: String,
        type: String,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> CatalogEntityIdentity? {
        let candidates = existing.filter {
            $0.entityType == .program && $0.catalogVersionID == catalogVersionID
        }
        guard !candidates.isEmpty else { return nil }

        let incomingPath = normalizedProgramURLPath(url)
        let incomingTitle = CatalogImportTransforms.normalize(name).lowercased()
        let incomingKey = displayKeyForProgram(url: url, name: name, type: type)

        if let exact = candidates.first(where: { $0.displayKey == incomingKey }) {
            return exact
        }

        var best: (identity: CatalogEntityIdentity, score: Double)?
        for candidate in candidates {
            let parts = candidate.displayKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let candidatePath = parts.first.map(String.init) ?? candidate.displayKey
            let candidateTitle = parts.count > 1 ? String(parts[1]) : ""

            var score = 0.0
            if !incomingPath.isEmpty, !candidatePath.isEmpty {
                if incomingPath == candidatePath {
                    score = 1.0
                } else if incomingPath.hasSuffix(candidatePath) || candidatePath.hasSuffix(incomingPath) {
                    score = max(score, programURLMatchThreshold)
                }
            }
            if score < programURLMatchThreshold,
               !incomingTitle.isEmpty,
               !candidateTitle.isEmpty {
                let titleScore = titleSimilarity(incomingTitle, candidateTitle)
                if titleScore >= programTitleMatchThreshold {
                    score = max(score, titleScore)
                }
            }
            if let current = best {
                if score > current.score {
                    best = (candidate, score)
                }
            } else if score >= programURLMatchThreshold {
                best = (candidate, score)
            }
        }
        return best?.identity
    }

    static func matchCourse(
        courseCode: String,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> CatalogEntityIdentity? {
        let incomingKey = displayKeyForCourse(courseCode: courseCode)
        guard !incomingKey.isEmpty else { return nil }
        let lookupKeys = Set(CatalogImportTransforms.catalogLookupCandidates(for: courseCode))
        return existing.first { identity in
            guard identity.entityType == .course,
                  identity.catalogVersionID == catalogVersionID else {
                return false
            }
            if identity.displayKey == incomingKey { return true }
            return lookupKeys.contains(identity.displayKey)
        }
    }

    static func resolveProgramIdentity(
        url: String,
        name: String,
        type: String,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> CatalogEntityIdentity {
        if let matched = matchProgram(
            url: url,
            name: name,
            type: type,
            catalogVersionID: catalogVersionID,
            existing: existing
        ) {
            return matched
        }
        return CatalogEntityIdentity(
            entityType: .program,
            catalogVersionID: catalogVersionID,
            displayKey: displayKeyForProgram(url: url, name: name, type: type)
        )
    }

    static func resolveCourseIdentity(
        courseCode: String,
        catalogVersionID: String,
        existing: [CatalogEntityIdentity]
    ) -> CatalogEntityIdentity {
        if let matched = matchCourse(
            courseCode: courseCode,
            catalogVersionID: catalogVersionID,
            existing: existing
        ) {
            return matched
        }
        return CatalogEntityIdentity(
            entityType: .course,
            catalogVersionID: catalogVersionID,
            displayKey: displayKeyForCourse(courseCode: courseCode)
        )
    }

    private static func normalizedProgramURLPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let url = URL(string: trimmed), let host = url.host {
            var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty, let fragment = url.fragment, !fragment.isEmpty {
                path = fragment
            }
            return "\(host.lowercased())/\(path.lowercased())"
        }
        return trimmed
            .lowercased()
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1.0 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            let shorter = Double(min(lhs.count, rhs.count))
            let longer = Double(max(lhs.count, rhs.count))
            return shorter / longer
        }
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}
