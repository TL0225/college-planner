// CatalogRepository+Writes.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — DepartmentUpsertInput.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7c/7d catalog write-through

extension CatalogRepository {
    struct DepartmentUpsertInput: Sendable {
        let id: UUID
        let name: String
        let code: String?
        let school: String?
    }

    struct MajorUpsertInput: Sendable {
        let id: UUID
        let name: String
        let degreeLevel: String
        let degreeType: String?
        let isMinor: Bool
        let programURL: String?
        let programURLs: String?
        let sourceCatoids: String?
        let resolvedDepartment: String?
        let resolvedCollege: String?
        let departmentIDs: [UUID]
        let catalogStableID: UUID?
        let provenanceJSON: String?
        let mappingConfidence: Double?
        let mappingSource: String?
    }

    func upsertDepartments(universityID: UUID, inputs: [DepartmentUpsertInput]) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID) != nil else { return }

        for input in inputs {
            let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            let department: Department
            if let existing = try fetchDepartment(id: input.id) {
                department = existing
            } else if let existing = try fetchDepartment(
                universityID: universityID,
                named: trimmedName
            ) {
                department = existing
            } else {
                department = Department(id: input.id, name: trimmedName)
                department.university = try fetchUniversity(id: universityID)
                context.insert(department)
            }

            department.name = trimmedName
            department.code = input.code
            if let school = input.school {
                department.school = school
            }
            department.lastUpdated = .now
        }

        ModelMergeCoalescer.scheduleSave(context)
    }

    func upsertMajors(universityID: UUID, inputs: [MajorUpsertInput]) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID) != nil else { return }

        for input in inputs {
            let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            let major: Major
            if let existing = try fetchMajor(id: input.id) {
                major = existing
            } else if let programURL = normalizedProgramURL(input.programURL),
                      let existing = try fetchMajor(universityID: universityID, programURL: programURL) {
                major = existing
            } else if let existing = try fetchMajor(
                universityID: universityID,
                name: trimmedName,
                degreeLevel: input.degreeLevel,
                isMinor: input.isMinor,
                degreeType: input.degreeType
            ) {
                major = existing
            } else {
                major = Major(
                    id: input.id,
                    name: trimmedName,
                    degreeLevel: input.degreeLevel,
                    isMinor: input.isMinor
                )
                major.university = try fetchUniversity(id: universityID)
                context.insert(major)
            }

            major.name = trimmedName
            major.degreeLevel = input.degreeLevel
            major.degreeType = input.degreeType
            major.isMinor = input.isMinor
            major.programURL = normalizedProgramURL(input.programURL)
            major.programURLs = input.programURLs
            major.sourceCatoids = input.sourceCatoids
            major.resolvedDepartment = input.resolvedDepartment
            major.resolvedCollege = input.resolvedCollege
            major.lastUpdated = .now
            if let stableID = input.catalogStableID {
                major.catalogStableID = stableID
            }
            if let provenanceJSON = input.provenanceJSON {
                major.provenanceJSON = provenanceJSON
            }
            if let mappingConfidence = input.mappingConfidence {
                major.mappingConfidence = mappingConfidence
            }
            if let mappingSource = input.mappingSource {
                major.mappingSource = mappingSource
            }

            let linkedDepartments = input.departmentIDs.compactMap { try? fetchDepartment(id: $0) }
            major.departments = linkedDepartments.isEmpty ? nil : linkedDepartments
        }

        ModelMergeCoalescer.scheduleSave(context)
    }

    private func fetchDepartment(id: UUID) throws -> Department? {
        var descriptor = FetchDescriptor<Department>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchDepartment(universityID: UUID, named name: String) throws -> Department? {
        var descriptor = FetchDescriptor<Department>(
            predicate: #Predicate { dept in
                dept.university?.id == universityID && dept.name == name
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMajor(id: UUID) throws -> Major? {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMajor(universityID: UUID, programURL: String) throws -> Major? {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID && major.programURL == programURL
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMajor(
        universityID: UUID,
        name: String,
        degreeLevel: String,
        isMinor: Bool,
        degreeType: String?
    ) throws -> Major? {
        let storedDegreeType = degreeType ?? ""
        if storedDegreeType.isEmpty {
            var descriptor = FetchDescriptor<Major>(
                predicate: #Predicate { major in
                    major.university?.id == universityID
                        && major.name == name
                        && major.degreeLevel == degreeLevel
                        && major.isMinor == isMinor
                        && major.degreeType == nil
                }
            )
            descriptor.fetchLimit = 1
            if let match = try context.fetch(descriptor).first {
                return match
            }
            var emptyTypeDescriptor = FetchDescriptor<Major>(
                predicate: #Predicate { major in
                    major.university?.id == universityID
                        && major.name == name
                        && major.degreeLevel == degreeLevel
                        && major.isMinor == isMinor
                        && major.degreeType == ""
                }
            )
            emptyTypeDescriptor.fetchLimit = 1
            return try context.fetch(emptyTypeDescriptor).first
        }

        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
                    && major.name == name
                    && major.degreeLevel == degreeLevel
                    && major.isMinor == isMinor
                    && major.degreeType == storedDegreeType
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func normalizedProgramURL(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}