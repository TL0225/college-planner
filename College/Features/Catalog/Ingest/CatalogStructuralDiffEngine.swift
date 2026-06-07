// CatalogStructuralDiffEngine.swift
// Feature: Catalog
// Purpose: Rename-aware structural diff via catalogStableID / display keys (Tier 2).
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogStructuralDiffReport: Codable, Sendable, Equatable {
    let schoolID: String
    let catalogVersionID: String
    let recordedAt: Date
    let programsAdded: Int
    let programsRemoved: Int
    let coursesAdded: Int
    let coursesRemoved: Int
    let programDisplayKeysAdded: [String]
    let programDisplayKeysRemoved: [String]
    let courseDisplayKeysAdded: [String]
    let courseDisplayKeysRemoved: [String]
    let programsRenamed: [CatalogEntityRename]
    let coursesRenamed: [CatalogEntityRename]

    var hasChanges: Bool {
        programsAdded > 0 || programsRemoved > 0 || coursesAdded > 0 || coursesRemoved > 0
            || !programsRenamed.isEmpty || !coursesRenamed.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case schoolID, catalogVersionID, recordedAt
        case programsAdded, programsRemoved, coursesAdded, coursesRemoved
        case programDisplayKeysAdded, programDisplayKeysRemoved
        case courseDisplayKeysAdded, courseDisplayKeysRemoved
        case programsRenamed, coursesRenamed
    }

    init(
        schoolID: String,
        catalogVersionID: String,
        recordedAt: Date,
        programsAdded: Int,
        programsRemoved: Int,
        coursesAdded: Int,
        coursesRemoved: Int,
        programDisplayKeysAdded: [String],
        programDisplayKeysRemoved: [String],
        courseDisplayKeysAdded: [String],
        courseDisplayKeysRemoved: [String],
        programsRenamed: [CatalogEntityRename] = [],
        coursesRenamed: [CatalogEntityRename] = []
    ) {
        self.schoolID = schoolID
        self.catalogVersionID = catalogVersionID
        self.recordedAt = recordedAt
        self.programsAdded = programsAdded
        self.programsRemoved = programsRemoved
        self.coursesAdded = coursesAdded
        self.coursesRemoved = coursesRemoved
        self.programDisplayKeysAdded = programDisplayKeysAdded
        self.programDisplayKeysRemoved = programDisplayKeysRemoved
        self.courseDisplayKeysAdded = courseDisplayKeysAdded
        self.courseDisplayKeysRemoved = courseDisplayKeysRemoved
        self.programsRenamed = programsRenamed
        self.coursesRenamed = coursesRenamed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schoolID = try container.decode(String.self, forKey: .schoolID)
        catalogVersionID = try container.decode(String.self, forKey: .catalogVersionID)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        programsAdded = try container.decode(Int.self, forKey: .programsAdded)
        programsRemoved = try container.decode(Int.self, forKey: .programsRemoved)
        coursesAdded = try container.decode(Int.self, forKey: .coursesAdded)
        coursesRemoved = try container.decode(Int.self, forKey: .coursesRemoved)
        programDisplayKeysAdded = try container.decode([String].self, forKey: .programDisplayKeysAdded)
        programDisplayKeysRemoved = try container.decode([String].self, forKey: .programDisplayKeysRemoved)
        courseDisplayKeysAdded = try container.decode([String].self, forKey: .courseDisplayKeysAdded)
        courseDisplayKeysRemoved = try container.decode([String].self, forKey: .courseDisplayKeysRemoved)
        programsRenamed = try container.decodeIfPresent([CatalogEntityRename].self, forKey: .programsRenamed) ?? []
        coursesRenamed = try container.decodeIfPresent([CatalogEntityRename].self, forKey: .coursesRenamed) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schoolID, forKey: .schoolID)
        try container.encode(catalogVersionID, forKey: .catalogVersionID)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(programsAdded, forKey: .programsAdded)
        try container.encode(programsRemoved, forKey: .programsRemoved)
        try container.encode(coursesAdded, forKey: .coursesAdded)
        try container.encode(coursesRemoved, forKey: .coursesRemoved)
        try container.encode(programDisplayKeysAdded, forKey: .programDisplayKeysAdded)
        try container.encode(programDisplayKeysRemoved, forKey: .programDisplayKeysRemoved)
        try container.encode(courseDisplayKeysAdded, forKey: .courseDisplayKeysAdded)
        try container.encode(courseDisplayKeysRemoved, forKey: .courseDisplayKeysRemoved)
        try container.encode(programsRenamed, forKey: .programsRenamed)
        try container.encode(coursesRenamed, forKey: .coursesRenamed)
    }
}

struct CatalogEntityRename: Codable, Sendable, Equatable {
    let stableID: UUID
    let previousDisplayKey: String
    let currentDisplayKey: String
}

enum CatalogStructuralDiffEngine {
    static func diff(
        schoolID: String,
        catalogVersionID: String,
        previous: [CatalogEntityIdentity],
        current: [CatalogEntityIdentity],
        recordedAt: Date = Date()
    ) -> CatalogStructuralDiffReport {
        let prevPrograms = keys(previous, type: .program)
        let currPrograms = keys(current, type: .program)
        let prevCourses = keys(previous, type: .course)
        let currCourses = keys(current, type: .course)

        let programRenames = renames(previous: previous, current: current, type: .program)
        let courseRenames = renames(previous: previous, current: current, type: .course)
        let renamedProgramPrevious = Set(programRenames.map(\.previousDisplayKey))
        let renamedProgramCurrent = Set(programRenames.map(\.currentDisplayKey))
        let renamedCoursePrevious = Set(courseRenames.map(\.previousDisplayKey))
        let renamedCourseCurrent = Set(courseRenames.map(\.currentDisplayKey))
        let addedPrograms = currPrograms.subtracting(prevPrograms).subtracting(renamedProgramCurrent).sorted()
        let removedPrograms = prevPrograms.subtracting(currPrograms).subtracting(renamedProgramPrevious).sorted()
        let addedCourses = currCourses.subtracting(prevCourses).subtracting(renamedCourseCurrent).sorted()
        let removedCourses = prevCourses.subtracting(currCourses).subtracting(renamedCoursePrevious).sorted()

        return CatalogStructuralDiffReport(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            recordedAt: recordedAt,
            programsAdded: addedPrograms.count,
            programsRemoved: removedPrograms.count,
            coursesAdded: addedCourses.count,
            coursesRemoved: removedCourses.count,
            programDisplayKeysAdded: addedPrograms,
            programDisplayKeysRemoved: removedPrograms,
            courseDisplayKeysAdded: addedCourses,
            courseDisplayKeysRemoved: removedCourses,
            programsRenamed: programRenames,
            coursesRenamed: courseRenames
        )
    }

    private static func keys(_ identities: [CatalogEntityIdentity], type: CatalogEntityType) -> Set<String> {
        Set(
            identities
                .filter { $0.entityType == type }
                .map(\.displayKey)
                .filter { !$0.isEmpty }
        )
    }

    private static func renames(
        previous: [CatalogEntityIdentity],
        current: [CatalogEntityIdentity],
        type: CatalogEntityType
    ) -> [CatalogEntityRename] {
        let previousByStable = Dictionary(
            uniqueKeysWithValues: previous
                .filter { $0.entityType == type }
                .map { ($0.stableID, $0.displayKey) }
        )
        var results: [CatalogEntityRename] = []
        for identity in current where identity.entityType == type {
            guard let priorKey = previousByStable[identity.stableID],
                  priorKey != identity.displayKey else { continue }
            results.append(
                CatalogEntityRename(
                    stableID: identity.stableID,
                    previousDisplayKey: priorKey,
                    currentDisplayKey: identity.displayKey
                )
            )
        }
        return results.sorted { $0.currentDisplayKey < $1.currentDisplayKey }
    }
}

enum CatalogStructuralDiffStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogDiffs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ report: CatalogStructuralDiffReport) {
        let safeSchool = report.schoolID.replacingOccurrences(of: "/", with: "_")
        let url = root.appendingPathComponent("\(safeSchool).json")
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(schoolID: String) -> CatalogStructuralDiffReport? {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let url = root.appendingPathComponent("\(safeSchool).json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogStructuralDiffReport.self, from: data) else {
            return nil
        }
        return decoded
    }
}
