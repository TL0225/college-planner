// CatalogSemanticDiffEngine.swift
// Feature: Catalog
// Purpose: Semantic catalog diff between editions atop structural diff (P20).

import Foundation

struct CatalogCreditChange: Sendable, Equatable {
    let key: String
    let before: Int
    let after: Int
}

struct CatalogSemanticDiff: Sendable, Equatable {
    let addedPrograms: [String]
    let removedPrograms: [String]
    let addedRequirements: [String]
    let removedRequirements: [String]
    let creditChanges: [CatalogCreditChange]
    let astChanges: [String]

    var changeCount: Int {
        addedPrograms.count + removedPrograms.count + addedRequirements.count
            + removedRequirements.count + creditChanges.count + astChanges.count
    }
}

enum CatalogSemanticDiffEngine {
    static func diff(
        beforePrograms: [String],
        afterPrograms: [String],
        beforeRequirements: [DegreeRequirement],
        afterRequirements: [DegreeRequirement]
    ) -> CatalogSemanticDiff {
        let beforeProgramSet = Set(beforePrograms.map { $0.lowercased() })
        let afterProgramSet = Set(afterPrograms.map { $0.lowercased() })
        let addedPrograms = afterPrograms.filter { !beforeProgramSet.contains($0.lowercased()) }
        let removedPrograms = beforePrograms.filter { !afterProgramSet.contains($0.lowercased()) }

        func reqKey(_ row: DegreeRequirement) -> String {
            "\(row.major.lowercased())||\(row.category.lowercased())"
        }
        let beforeReqMap = Dictionary(uniqueKeysWithValues: beforeRequirements.map { (reqKey($0), $0) })
        let afterReqMap = Dictionary(uniqueKeysWithValues: afterRequirements.map { (reqKey($0), $0) })
        let beforeKeys = Set(beforeReqMap.keys)
        let afterKeys = Set(afterReqMap.keys)
        let addedRequirements = afterKeys.subtracting(beforeKeys).sorted()
        let removedRequirements = beforeKeys.subtracting(afterKeys).sorted()

        var creditChanges: [CatalogCreditChange] = []
        var astChanges: [String] = []
        for key in beforeKeys.intersection(afterKeys) {
            guard let before = beforeReqMap[key], let after = afterReqMap[key] else { continue }
            if before.creditsRequired != after.creditsRequired {
                creditChanges.append(CatalogCreditChange(key: key, before: before.creditsRequired, after: after.creditsRequired))
            }
            let beforeAST = CatalogRequirementAST.encode(before.requirementPredicate)
            let afterAST = CatalogRequirementAST.encode(after.requirementPredicate)
            if beforeAST != afterAST {
                astChanges.append(key)
            }
        }

        return CatalogSemanticDiff(
            addedPrograms: addedPrograms.sorted(),
            removedPrograms: removedPrograms.sorted(),
            addedRequirements: addedRequirements,
            removedRequirements: removedRequirements,
            creditChanges: creditChanges,
            astChanges: astChanges.sorted()
        )
    }
}
