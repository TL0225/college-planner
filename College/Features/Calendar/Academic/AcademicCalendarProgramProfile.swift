// AcademicCalendarProgramProfile.swift
// Feature: Calendar
// Purpose: Catalog-derived program ownership for academic calendar link resolution.

import Foundation
import SwiftData

struct AcademicCalendarProgramProfile: Sendable, Equatable {
  var degreeLevel: String?
  var levelScope: AcademicCalendarLevelScope
  var programLabel: String?
  var owningCollege: String?
  var owningDepartment: String?
  var owningSchool: String?
  var matchTokens: [String]
  var isDegraded: Bool
  var departmentKey: String
  var departmentDisplayName: String

  var fingerprintSeed: String {
    [degreeLevel, owningCollege, owningDepartment, programLabel]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "|")
      .lowercased()
  }

  @MainActor
  static func resolve(persistence: CollegePersistence) -> AcademicCalendarProgramProfile? {
    let base = AcademicCalendarProgramContext.resolve(persistence: persistence)
    let profile = persistence.academicProfiles.first(where: \.isPrimary)
      ?? persistence.academicProfiles.first
    let majors = profile.map { AcademicProfileProgramLists.majors(from: $0) } ?? []
    let programLabel = majors.first?.trimmingCharacters(in: .whitespacesAndNewlines)

    let universityName = persistence.getActiveUniversityName()?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    var owningCollege: String?
    var owningDepartment: String?
    var owningSchool: String?
    var isDegraded = true

    if let universityName, !universityName.isEmpty,
       let programLabel, !programLabel.isEmpty,
       let major = lookupMajor(
         programDisplay: programLabel,
         universityName: universityName,
         degreeLevel: base?.degreeLevel,
         degreeType: profile?.degreeType,
         isMinor: false
       ) {
      owningCollege = major.resolvedCollege?.trimmingCharacters(in: .whitespacesAndNewlines)
      owningDepartment = major.resolvedDepartment?.trimmingCharacters(in: .whitespacesAndNewlines)
      owningSchool = major.departments?.first?.school?.trimmingCharacters(in: .whitespacesAndNewlines)
      if owningCollege != nil || owningDepartment != nil {
        isDegraded = false
      }
    }

    var labelSources = [owningCollege, owningDepartment, owningSchool, programLabel]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if labelSources.isEmpty, let programLabel, !programLabel.isEmpty {
      labelSources = [programLabel]
    }

    let matchTokens = AcademicCalendarNormalization.matchTokens(from: labelSources)
    let departmentDisplayName = deriveDepartmentDisplayName(
      college: owningCollege,
      department: owningDepartment,
      program: programLabel,
      universityName: universityName
    )
    let departmentKey: String
    if let college = owningCollege, !college.isEmpty {
      departmentKey = AcademicCalendarNormalization.slugKey(from: college)
    } else if let department = owningDepartment, !department.isEmpty {
      departmentKey = AcademicCalendarNormalization.slugKey(from: department)
    } else {
      departmentKey = AcademicCalendarConfig.universityWideKey
    }

    guard base != nil || !matchTokens.isEmpty else { return nil }

    return AcademicCalendarProgramProfile(
      degreeLevel: base?.degreeLevel,
      levelScope: base?.levelScope ?? .all,
      programLabel: programLabel,
      owningCollege: owningCollege,
      owningDepartment: owningDepartment,
      owningSchool: owningSchool,
      matchTokens: matchTokens,
      isDegraded: isDegraded,
      departmentKey: departmentKey,
      departmentDisplayName: departmentDisplayName
    )
  }

  static func departmentKey(from hubLabel: String) -> String {
    let trimmed = hubLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return AcademicCalendarConfig.universityWideKey }
    return AcademicCalendarNormalization.slugKey(from: trimmed)
  }

  static func departmentDisplayName(from hubLabel: String, schoolName: String) -> String {
    let trimmed = hubLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "\(schoolName) Term Dates" }
    if trimmed.localizedCaseInsensitiveContains("calendar") {
      return trimmed
    }
    return "\(trimmed) — Term Dates"
  }

  private static func deriveDepartmentDisplayName(
    college: String?,
    department: String?,
    program: String?,
    universityName: String?
  ) -> String {
    if let college, !college.isEmpty { return "\(college) — Term Dates" }
    if let department, !department.isEmpty { return "\(department) — Term Dates" }
    if let universityName, !universityName.isEmpty { return "\(universityName) Term Dates" }
    if let program, !program.isEmpty { return "\(program) — Term Dates" }
    return "University Term Dates"
  }

  @MainActor
  private static func lookupMajor(
    programDisplay: String,
    universityName: String,
    degreeLevel: String?,
    degreeType: String?,
    isMinor: Bool
  ) -> Major? {
    guard let repo = AppDataStore.shared.catalogRepository,
          let university = try? repo.fetchUniversity(named: universityName),
          let majors = try? repo.fetchAllMajors(universityID: university.id) else {
      return nil
    }
    let target = programDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = CatalogProgramNameHelpers.cleanedProgramName(from: target, degreeType: degreeType)

    func matches(_ major: Major) -> Bool {
      guard major.isMinor == isMinor else { return false }
      let name = major.name.trimmingCharacters(in: .whitespacesAndNewlines)
      if name.caseInsensitiveCompare(cleaned) == .orderedSame { return true }
      if name.caseInsensitiveCompare(target) == .orderedSame { return true }
      if let level = degreeLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !level.isEmpty {
        return major.degreeLevel.caseInsensitiveCompare(level) == .orderedSame
          && name.localizedCaseInsensitiveContains(cleaned)
      }
      return false
    }

    return majors.first(where: matches)
  }
}
