// RequirementBreakdownBuilder.swift
// Feature: Academics
// Purpose: Academics module — BreakdownCategory.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Builds Requirements Breakdown categories from scraped `DegreeRequirement` rows (test + validator parity with Academics).
enum RequirementBreakdownBuilder {
    struct BreakdownCategory: Sendable, Equatable {
        let title: String
        let itemCodes: [String]
        let selectCount: Int
        let progressTarget: Int
        let descriptionCredits: Int
    }

    static func visibleCategories(from requirements: [DegreeRequirement]) -> [BreakdownCategory] {
        struct ReqGroup {
            var codes: [String] = []
            var electiveCodes: [String] = []
            var selectN: Int = 0
            var description: String = ""
            var descriptionCredits: Int = 0
        }

        func dedupeCodes(_ codes: [String]) -> [String] {
            var seen = Set<String>()
            var out: [String] = []
            for raw in codes {
                let c = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !c.isEmpty, seen.insert(c).inserted else { continue }
                out.append(c)
            }
            return out
        }

        var orderedKeys: [String] = []
        var grouped: [String: ReqGroup] = [:]

        for req in requirements {
            let cat = req.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if cat.isEmpty || cat == "__PROGRAM_TOTAL_CREDITS__" { continue }

            let rowDescription = (req.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let codes = req.requiredCourses ?? []
            let electiveCodes = req.selectFrom ?? []
            let selectN = req.selectCount ?? 0
            let proseCredits = RequirementBreakdownCredits.creditsMentionedInProse(rowDescription)
            let storedCredits = req.creditsRequired
            let effectiveDescriptionCredits = max(proseCredits, storedCredits)

            if grouped[cat] == nil {
                orderedKeys.append(cat)
                grouped[cat] = ReqGroup(
                    codes: codes,
                    electiveCodes: electiveCodes,
                    selectN: selectN,
                    description: rowDescription,
                    descriptionCredits: effectiveDescriptionCredits
                )
            } else {
                grouped[cat]?.codes.append(contentsOf: codes)
                grouped[cat]?.electiveCodes.append(contentsOf: electiveCodes)
                if selectN > (grouped[cat]?.selectN ?? 0) { grouped[cat]?.selectN = selectN }
                if effectiveDescriptionCredits > (grouped[cat]?.descriptionCredits ?? 0) {
                    grouped[cat]?.descriptionCredits = effectiveDescriptionCredits
                }
                if rowDescription.count > (grouped[cat]?.description.count ?? 0) {
                    grouped[cat]?.description = rowDescription
                }
            }
        }

        var categories: [BreakdownCategory] = []
        for key in orderedKeys {
            guard let group = grouped[key] else { continue }
            let shownCodes = dedupeCodes(group.codes)
            let electiveShown = dedupeCodes(group.electiveCodes)
            let proseCredits = group.descriptionCredits
            guard !shownCodes.isEmpty || !electiveShown.isEmpty || proseCredits > 0 else { continue }

            var items: [(code: String, credits: Int, isElective: Bool)] = []
            for code in shownCodes {
                let detailed = requirements
                    .flatMap { ($0.requiredCoursesDetailed ?? []) }
                    .first { $0.code.uppercased() == code.uppercased() }
                let cr = RequirementBreakdownCredits.creditValue(from: detailed?.credits ?? "")
                items.append((code, cr > 0 ? cr : 3, false))
            }
            for code in electiveShown {
                let detailed = requirements
                    .flatMap { ($0.selectFromDetailed ?? []) }
                    .first { $0.code.uppercased() == code.uppercased() }
                let cr = RequirementBreakdownCredits.creditValue(from: detailed?.credits ?? "")
                items.append((code, cr > 0 ? cr : 3, true))
            }

            let kind = requirements.first(where: { $0.category == key })?.requirementKind
            let storedCredits = requirements.first(where: { $0.category == key })?.creditsRequired ?? 0
            let auditItems = items.map { item in
                AcademicsAuditPanel.AuditItem(
                    code: item.code,
                    credits: item.credits > 0 ? "\(item.credits)" : "",
                    title: "",
                    grade: nil,
                    planProgress: .notOnPlan,
                    isElective: item.isElective
                )
            }

            var target = RequirementBreakdownCredits.progressTarget(
                items: auditItems,
                selectCount: group.selectN,
                descriptionCredits: proseCredits,
                headerCredits: kind == .chooseOne ? storedCredits : 0
            )
            switch kind {
            case .chooseOne where storedCredits > 0:
                target = storedCredits
            case .distributionBucket, .ruleBucket:
                target = max(target, storedCredits)
            default:
                break
            }

            categories.append(
                BreakdownCategory(
                    title: key,
                    itemCodes: shownCodes + electiveShown,
                    selectCount: group.selectN,
                    progressTarget: target,
                    descriptionCredits: proseCredits
                )
            )
        }

        return categories
    }
}
