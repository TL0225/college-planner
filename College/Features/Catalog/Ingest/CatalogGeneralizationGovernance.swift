// CatalogGeneralizationGovernance.swift
// Feature: Catalog
// Purpose: No-hardcoding guard and CI promotion rules (P14).

import Foundation

enum CatalogGeneralizationGovernance {
    private static let forbiddenPatterns: [String] = [
        #"if\s+schoolID\s*==\s*"fordham"#,
        #"case\s+"fordham_university""#,
        #"schoolID\s*==\s*"cmu"#,
    ]

    struct Violation: Sendable, Equatable {
        let file: String
        let pattern: String
        let line: Int
    }

    static func scanSourceFiles(_ contentsByPath: [String: String]) -> [Violation] {
        var violations: [Violation] = []
        for (path, contents) in contentsByPath {
            guard path.contains("/Catalog/") else { continue }
            let lines = contents.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                for pattern in forbiddenPatterns {
                    if line.range(of: pattern, options: .regularExpression) != nil {
                        violations.append(Violation(file: path, pattern: pattern, line: index + 1))
                    }
                }
            }
        }
        return violations
    }

    static func corpusCIPromotionThreshold(oqs: Double, tier: CatalogSchoolTier) -> Bool {
        switch tier {
        case .development: return oqs >= 0.55
        case .validation: return oqs >= 0.65
        case .heldOut: return oqs >= 0.70
        }
    }
}
