// RequirementFulfillmentStore.swift
// Feature: Academics
// Purpose: Academics module — RequirementFulfillmentAssignmentSource.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension Notification.Name {
    static let requirementFulfillmentChanged = Notification.Name("requirementFulfillmentChanged")
}

enum RequirementFulfillmentAssignmentSource: String, Sendable {
    case userAssumed
    case catalogListed
}

enum RequirementFulfillmentStore {

    static func assign(
        context: ModelContext,
        university: String,
        programURL: String,
        requirementCategory: String,
        courseCode: String,
        source: RequirementFulfillmentAssignmentSource = .userAssumed
    ) throws {
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedCategory = requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty, !normalizedCategory.isEmpty else { return }

        let universityTrimmed = university.trimmingCharacters(in: .whitespacesAndNewlines)
        let programTrimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<RequirementFulfillment> { row in
            row.university == universityTrimmed
                && row.programURL == programTrimmed
                && row.requirementCategory == normalizedCategory
                && row.courseCode == normalizedCode
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        if (try context.fetch(descriptor)).isEmpty {
            context.insert(
                RequirementFulfillment(
                    university: universityTrimmed,
                    programURL: programTrimmed,
                    requirementCategory: normalizedCategory,
                    courseCode: normalizedCode,
                    assignmentSource: source.rawValue
                )
            )
        }
        try context.save()
        NotificationCenter.default.post(name: .requirementFulfillmentChanged, object: nil)
    }

    static func remove(
        context: ModelContext,
        university: String,
        programURL: String,
        requirementCategory: String,
        courseCode: String
    ) throws {
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedCategory = requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let universityTrimmed = university.trimmingCharacters(in: .whitespacesAndNewlines)
        let programTrimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<RequirementFulfillment> { row in
            row.university == universityTrimmed
                && row.programURL == programTrimmed
                && row.requirementCategory == normalizedCategory
                && row.courseCode == normalizedCode
        }
        for row in try context.fetch(FetchDescriptor(predicate: predicate)) {
            context.delete(row)
        }
        try context.save()
        NotificationCenter.default.post(name: .requirementFulfillmentChanged, object: nil)
    }

    static func assignments(
        context: ModelContext,
        university: String,
        programURL: String,
        requirementCategory: String
    ) -> [RequirementFulfillment] {
        let normalizedCategory = requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let universityTrimmed = university.trimmingCharacters(in: .whitespacesAndNewlines)
        let programTrimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<RequirementFulfillment> { row in
            row.university == universityTrimmed
                && row.programURL == programTrimmed
                && row.requirementCategory == normalizedCategory
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func allAssignments(
        context: ModelContext,
        university: String,
        programURL: String
    ) -> [RequirementFulfillment] {
        let universityTrimmed = university.trimmingCharacters(in: .whitespacesAndNewlines)
        let programTrimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<RequirementFulfillment> { row in
            row.university == universityTrimmed && row.programURL == programTrimmed
        }
        return (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    }

    static func allAssignedCodes(
        context: ModelContext,
        university: String,
        programURL: String
    ) -> Set<String> {
        Set(
            allAssignments(context: context, university: university, programURL: programURL)
                .map { $0.courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }
}
