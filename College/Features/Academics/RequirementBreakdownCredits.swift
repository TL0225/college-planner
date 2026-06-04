// RequirementBreakdownCredits.swift
// Feature: Academics
// Purpose: Academics module — RequirementBreakdownCredits.
// Data: CollegePersistence / repositories when applicable.

// RequirementBreakdownCredits.swift
// App-computed credit targets for the Requirements Breakdown and degree-progress
// summaries. Scraper-stored `creditsRequired` and "(N Credits)" category titles are
// not used for progress denominators — only enumerated courses, choose-N rules, and
// credit amounts parsed from requirement descriptions.

import Foundation

enum RequirementBreakdownCredits {
    private static let defaultCreditsPerCourse = 3

    // MARK: - Parsing

    static func creditValue(from raw: String) -> Int {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        if let direct = Double(text) { return Int(direct.rounded()) }
        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let tokenRange = Range(match.range, in: text),
              let numeric = Double(text[tokenRange]) else { return 0 }
        return Int(numeric.rounded())
    }

    /// Pulls the first explicit "N credits" / "N cr" mention from catalog prose when
    /// no course codes were scraped for that row.
    static func creditsMentionedInProse(_ text: String) -> Int {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return 0 }

        let patterns = [
            #"(?i)(\d+(?:\.\d+)?)\s*credits?"#,
            #"(?i)(\d+(?:\.\d+)?)\s*cr\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: range),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: normalized),
               let value = Double(normalized[r]), value > 0 {
                return Int(value.rounded())
            }
        }
        return 0
    }

    // MARK: - Audit panel (SwiftUI items)

    static func sumCreditsAll(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        summedRequiredCredits(items: items.filter { !$0.isElective })
            + items.filter(\.isElective).map { creditValue(from: $0.credits) }.reduce(0, +)
    }

    /// Required rows that share an `alternativeGroupKey` count once (catalog OR alternatives).
    private static func summedRequiredCredits(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        var total = 0
        var seenOrGroups = Set<String>()
        for item in items {
            if let key = item.alternativeGroupKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                guard seenOrGroups.insert(key).inserted else { continue }
                let groupValues = items
                    .filter { $0.alternativeGroupKey == key }
                    .map { creditValue(from: $0.credits) }
                    .filter { $0 > 0 }
                total += groupValues.max() ?? defaultCreditsPerCourse
            } else {
                total += creditValue(from: item.credits)
            }
        }
        return total
    }

    static func sumCompletedCredits(
        items: [AcademicsAuditPanel.AuditItem],
        selectCount: Int = 0,
        descriptionCredits: Int = 0,
        headerCredits: Int = 0
    ) -> Int {
        let required = items.filter { !$0.isElective }
        let elective = items.filter(\.isElective)
        var completed = summedCompletedRequiredCredits(items: required)

        if selectCount > 0 {
            let completedElectiveValues = elective
                .filter(\.isCompleted)
                .map { creditValue(from: $0.credits) }
                .filter { $0 > 0 }
                .sorted(by: >)
            let pick = min(selectCount, completedElectiveValues.count)
            completed += completedElectiveValues.prefix(pick).reduce(0, +)
            if headerCredits > 0 {
                return min(headerCredits, completed)
            }
            if descriptionCredits > 0, pick > 0 {
                return min(descriptionCredits, completed)
            }
        } else {
            completed += elective.filter(\.isCompleted).map { creditValue(from: $0.credits) }.reduce(0, +)
        }
        return completed
    }

    private static func summedCompletedRequiredCredits(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        var total = 0
        var seenOrGroups = Set<String>()
        for item in items where item.isCompleted {
            if let key = item.alternativeGroupKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                guard seenOrGroups.insert(key).inserted else { continue }
                let groupValues = items
                    .filter { $0.alternativeGroupKey == key && $0.isCompleted }
                    .map { creditValue(from: $0.credits) }
                    .filter { $0 > 0 }
                total += groupValues.max() ?? 0
            } else {
                total += creditValue(from: item.credits)
            }
        }
        return total
    }

    static func sumCompletedCredits(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        sumCompletedCredits(items: items, selectCount: 0, descriptionCredits: 0, headerCredits: 0)
    }

    /// Target credits for a breakdown category from listed courses and prose.
    static func progressTarget(
        items: [AcademicsAuditPanel.AuditItem],
        selectCount: Int,
        descriptionCredits: Int,
        headerCredits: Int = 0
    ) -> Int {
        let required = items.filter { !$0.isElective }
        let elective = items.filter(\.isElective)

        var target = summedRequiredCredits(items: required)
        let electiveValues = elective.map { creditValue(from: $0.credits) }.filter { $0 > 0 }

        if selectCount > 0 {
            if headerCredits > 0 {
                return max(target, headerCredits)
            }
            if !electiveValues.isEmpty {
                let sorted = electiveValues.sorted(by: >)
                let pick = min(selectCount, sorted.count)
                target += sorted.prefix(pick).reduce(0, +)
            } else if descriptionCredits > 0 {
                // Catalog prose elective (e.g. "Choose two … 6 credits") with no listed codes.
                target += descriptionCredits
            } else {
                target += selectCount * defaultCreditsPerCourse
            }
        } else {
            target += electiveValues.reduce(0, +)
            if target == 0, descriptionCredits > 0 {
                target = descriptionCredits
            }
        }

        return target
    }

    static func progressTarget(for category: AcademicsAuditPanel.AuditCategory) -> Int {
        let fromItems = progressTarget(
            items: category.items,
            selectCount: category.selectCount,
            descriptionCredits: category.descriptionCredits,
            headerCredits: category.headerCredits
        )

        switch category.rowKind {
        case .some(.distributionBucket), .some(.ruleBucket):
            if category.catalogCreditsRequired > 0 {
                return category.catalogCreditsRequired
            }
            let catalog = max(category.catalogCreditsRequired, category.creditsRequired)
            return max(fromItems, catalog)
        case .some(.chooseOne):
            if category.headerCredits > 0 {
                return category.headerCredits
            }
            if category.catalogCreditsRequired > 0 {
                return category.catalogCreditsRequired
            }
            return max(fromItems, category.creditsRequired)
        default:
            return fromItems
        }
    }

    static func isCategoryDone(category: AcademicsAuditPanel.AuditCategory) -> Bool {
        let completed = sumCompletedCredits(
            items: category.items,
            selectCount: category.selectCount,
            descriptionCredits: category.descriptionCredits,
            headerCredits: category.headerCredits
        )
        let target = progressTarget(for: category)
        guard target > 0 else { return false }
        return completed >= target
    }

    // MARK: - local store requirement rows (degree-progress summaries)

    /// Same rules as the audit sidebar, for a grouped `DegreeRequirementEntity` section.
    static func categoryTarget(
        requiredCreditValues: [Int],
        electiveCreditValues: [Int],
        selectCount: Int,
        descriptionCredits: Int
    ) -> Int {
        var items: [AcademicsAuditPanel.AuditItem] = []
        for (idx, cr) in requiredCreditValues.enumerated() {
            items.append(
                AcademicsAuditPanel.AuditItem(
                    code: "R\(idx)",
                    credits: cr > 0 ? "\(cr)" : "",
                    title: "",
                    grade: nil,
                    planProgress: .notOnPlan,
                    isElective: false
                )
            )
        }
        for (idx, cr) in electiveCreditValues.enumerated() {
            items.append(
                AcademicsAuditPanel.AuditItem(
                    code: "E\(idx)",
                    credits: cr > 0 ? "\(cr)" : "",
                    title: "",
                    grade: nil,
                    planProgress: .notOnPlan,
                    isElective: true
                )
            )
        }
        return progressTarget(items: items, selectCount: selectCount, descriptionCredits: descriptionCredits)
    }
}
