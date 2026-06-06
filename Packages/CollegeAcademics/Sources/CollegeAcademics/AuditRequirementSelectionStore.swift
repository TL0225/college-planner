// AuditRequirementSelectionStore.swift
// Feature: Academics
// Purpose: Academics module — AuditRequirementSelectionStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Persists which catalog-listed courses the student picked for choose/select/OR rows
/// in the Requirements Breakdown (separate from drag-and-drop fulfillment assignments).
public enum AuditRequirementSelectionStore {
    private static let prefix = "academics.audit.requirementSelection.v1."

    private static func storageKey(degreeKey: String, categoryTitle: String) -> String {
        let degreeNorm = degreeKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let categoryNorm = categoryTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(prefix)\(degreeNorm)|\(categoryNorm)"
    }

    public static func selectedCodes(degreeKey: String, categoryTitle: String) -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: storageKey(degreeKey: degreeKey, categoryTitle: categoryTitle)) ?? []
        return Set(
            raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }

    public static func setSelectedCodes(_ codes: Set<String>, degreeKey: String, categoryTitle: String) {
        let normalized = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
            .sorted()
        UserDefaults.standard.set(normalized, forKey: storageKey(degreeKey: degreeKey, categoryTitle: categoryTitle))
    }

    /// Toggle or switch a listed course for a choose/select/OR row.
    public static func selectCourse(
        _ code: String,
        degreeKey: String,
        categoryTitle: String,
        maxSelections: Int,
        orGroupKey: String?,
        orGroupCodes: Set<String>
    ) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }

        var selected = selectedCodes(degreeKey: degreeKey, categoryTitle: categoryTitle)

        if let orGroupKey, !orGroupKey.isEmpty {
            let groupCodes = orGroupCodes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
            if selected.contains(normalized) {
                selected.remove(normalized)
            } else {
                selected.subtract(groupCodes)
                selected.insert(normalized)
            }
            setSelectedCodes(selected, degreeKey: degreeKey, categoryTitle: categoryTitle)
            return
        }

        if selected.contains(normalized) {
            selected.remove(normalized)
            setSelectedCodes(selected, degreeKey: degreeKey, categoryTitle: categoryTitle)
            return
        }

        let cap = max(1, maxSelections)
        if selected.count >= cap {
            if cap == 1, let existing = selected.first {
                selected.remove(existing)
            } else {
                return
            }
        }
        selected.insert(normalized)
        setSelectedCodes(selected, degreeKey: degreeKey, categoryTitle: categoryTitle)
    }
}
