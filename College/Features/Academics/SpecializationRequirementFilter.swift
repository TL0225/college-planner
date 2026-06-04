// SpecializationRequirementFilter.swift
// Feature: Academics
// Purpose: Academics module — CatBucket.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Drops specialization rows the user did not choose (Phase 7f — local store requirements).
enum SpecializationRequirementFilter {
    static func apply(
        requirements: [CatalogDegreeRequirement],
        degreeKey: String
    ) -> [CatalogDegreeRequirement] {
        guard !requirements.isEmpty else { return requirements }

        let resolvedKey: String = {
            let trimmed = degreeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let url = requirements.first?.programURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                return url
            }
            let major = requirements.first?.major.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return major
        }()
        guard !resolvedKey.isEmpty else { return requirements }

        struct CatBucket {
            var description: String = ""
            var sectionOrder: Int = .max
        }
        var byCategory: [String: CatBucket] = [:]
        var orderedTitles: [String] = []

        for req in requirements {
            if let kindRaw = req.requirementKind,
               let kind = RequirementKind(rawValue: kindRaw),
               kind == .distributionBucket || kind == .ruleBucket || kind == .chooseOne {
                continue
            }
            let selectCount = Int(req.selectCount)
            if selectCount > 0,
               !(req.selectFromJSON ?? "").isEmpty || !(req.selectFromDetailedJSON ?? "").isEmpty {
                continue
            }
            let title = req.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let rowDesc = (req.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if byCategory[title] == nil {
                byCategory[title] = CatBucket(description: rowDesc, sectionOrder: Int(req.sectionOrder))
                orderedTitles.append(title)
            } else {
                if rowDesc.count > (byCategory[title]?.description.count ?? 0) {
                    byCategory[title]?.description = rowDesc
                }
                let sectionOrder = Int(req.sectionOrder)
                if sectionOrder < (byCategory[title]?.sectionOrder ?? .max) {
                    byCategory[title]?.sectionOrder = sectionOrder
                }
            }
        }
        guard !orderedTitles.isEmpty else { return requirements }

        let placeholders = orderedTitles.map { title -> AcademicsAuditPanel.AuditCategory in
            AcademicsAuditPanel.AuditCategory(
                title: title,
                items: [],
                selectCount: 0,
                creditsRequired: 0,
                descriptionCredits: 0,
                specializationGroupKey: nil,
                specializationGroupTitle: nil
            )
        }
        let descriptions = orderedTitles.reduce(into: [String: String]()) { acc, title in
            acc[title] = byCategory[title]?.description ?? ""
        }
        let tagged = SpecializationGroupDetector.tagSpecializations(
            categories: placeholders,
            groupDescriptions: descriptions
        )
        let groupedCategories = tagged.filter { $0.specializationGroupKey != nil }
        guard !groupedCategories.isEmpty else { return requirements }

        let groupKeys = Set(groupedCategories.compactMap(\.specializationGroupKey))
        var keepInGroup: [String: Set<String>] = [:]
        for groupKey in groupKeys {
            let options = groupedCategories.filter { $0.specializationGroupKey == groupKey }
            let chosenTitle: String = AuditSpecializationStore
                .selectedOptionTitle(degreeKey: resolvedKey, groupKey: groupKey)
                ?? options.first?.title
                ?? ""
            keepInGroup[groupKey] = Set([chosenTitle])
        }

        var dropTitles = Set<String>()
        for cat in groupedCategories {
            guard let groupKey = cat.specializationGroupKey else { continue }
            if let keep = keepInGroup[groupKey], !keep.contains(cat.title) {
                dropTitles.insert(cat.title)
            }
        }
        guard !dropTitles.isEmpty else { return requirements }

        return requirements.filter { row in
            let title = row.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            return !dropTitles.contains(title)
        }
    }
}
