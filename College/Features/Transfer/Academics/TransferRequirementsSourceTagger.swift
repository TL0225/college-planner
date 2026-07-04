// TransferRequirementsSourceTagger.swift
// Feature: Transfer / Academics
// Purpose: Maps transfer equivalency provenance onto Requirements Breakdown course rows.

import Foundation

/// Human-readable source badge shown beside requirement rows when transfer data exists.
enum TransferRequirementsSourceLabel: String, Sendable {
    case official = "Official"
    case assist = "ASSIST"
    case transferology = "Transferology"
    case community = "Community"
    case yours = "Yours"

    static func label(for dto: TransferEquivalencyDTO) -> TransferRequirementsSourceLabel {
        switch dto.sourceKind {
        case .assist:
            return .assist
        case .tesPublicView, .banner8Articulation, .banner9SSB:
            return .official
        case .manualEntry:
            return .transferology
        case .communityImport, .githubDataset:
            if dto.verificationStatus == .verified || dto.sourceTier == .communityVerified {
                return .community
            }
            return .community
        }
    }

    var displayTitle: String { rawValue }
}

/// Builds a normalized target-course-code → source-label map from persisted equivalencies.
@MainActor
enum TransferRequirementsSourceTagger {
    static func sourceLabelsByTargetCourseCode(
        targetSchoolID: String,
        persistence: CollegePersistence
    ) -> [String: TransferRequirementsSourceLabel] {
        let repo = persistence.transferRepository
        let rows = (try? repo.fetchEquivalencies(
            targetSchoolID: targetSchoolID,
            limit: 5000
        )) ?? []
        var map: [String: TransferRequirementsSourceLabel] = [:]
        for row in rows where !row.isArchived {
            let normalized = CatalogImportTransforms.normalizeCourseCode(row.targetCourseCode)
            guard !normalized.isEmpty else { continue }
            let dto = repo.makeDTO(from: row)
            let label = TransferRequirementsSourceLabel.label(for: dto)
            if let existing = map[normalized] {
                map[normalized] = preferred(existing, label)
            } else {
                map[normalized] = label
            }
        }
        return map
    }

    static func applySourceTags(
        to degrees: [AcademicsAuditPanel.AuditDegree],
        labelsByCode: [String: TransferRequirementsSourceLabel]
    ) -> [AcademicsAuditPanel.AuditDegree] {
        guard !labelsByCode.isEmpty else { return degrees }
        return degrees.map { degree in
            var categories = degree.categories
            categories = categories.map { category in
                let items = category.items.map { item -> AcademicsAuditPanel.AuditItem in
                    let key = CatalogImportTransforms.normalizeCourseCode(item.code)
                    guard let label = labelsByCode[key] else { return item }
                    return AcademicsAuditPanel.AuditItem(
                        code: item.code,
                        credits: item.credits,
                        title: item.title,
                        grade: item.grade,
                        planProgress: item.planProgress,
                        isElective: item.isElective,
                        alternativeGroupKey: item.alternativeGroupKey,
                        transferSourceLabel: label.displayTitle
                    )
                }
                return AcademicsAuditPanel.AuditCategory(
                    title: category.title,
                    items: items,
                    selectCount: category.selectCount,
                    creditsRequired: category.creditsRequired,
                    catalogCreditsRequired: category.catalogCreditsRequired,
                    descriptionCredits: category.descriptionCredits,
                    headerCredits: category.headerCredits,
                    rowKind: category.rowKind,
                    parentSectionTitle: category.parentSectionTitle,
                    displayTitle: category.displayTitle,
                    sectionHeader: category.sectionHeader,
                    indentLevel: category.indentLevel,
                    allowsManualFulfillment: category.allowsManualFulfillment,
                    specializationGroupKey: category.specializationGroupKey,
                    specializationGroupTitle: category.specializationGroupTitle
                )
            }
            return AcademicsAuditPanel.AuditDegree(
                label: degree.label,
                rawName: degree.rawName,
                kind: degree.kind,
                color: degree.color,
                categories: categories,
                programURL: degree.programURL,
                degreeType: degree.degreeType,
                isGraduationRequirement: degree.isGraduationRequirement
            )
        }
    }

    private static func preferred(
        _ lhs: TransferRequirementsSourceLabel,
        _ rhs: TransferRequirementsSourceLabel
    ) -> TransferRequirementsSourceLabel {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private static func rank(_ label: TransferRequirementsSourceLabel) -> Int {
        switch label {
        case .official, .assist: return 4
        case .transferology: return 3
        case .community: return 2
        case .yours: return 1
        }
    }
}
