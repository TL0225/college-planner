// AcademicCalendarImportCoordinator.swift
// Feature: Calendar
// Purpose: Import university term dates using the active school + program catalog context.

import CollegeCalendar
import Foundation

@MainActor
enum AcademicCalendarImportCoordinator {
  static func canOfferImport(persistence: CollegePersistence) -> Bool {
    guard AcademicCalendarSyncEligibility.gate(persistence: persistence).isReady else { return false }
    guard resolveCalendarURLSync(persistence: persistence) != nil else { return false }
    if let config = existingConfig(persistence: persistence),
       let last = config.lastSuccessfulAt,
       config.lastSuccessfulEventCount > 0,
       Date().timeIntervalSince(last) < 7 * 24 * 60 * 60 {
      return false
    }
    return true
  }

  @discardableResult
  static func importTermDates(
    persistence: CollegePersistence,
    calendarManager: CalendarIntegrationManager,
    writeChanges: Bool = true,
    urlOverride: String? = nil,
    departmentKey: String? = nil,
    hubPickerNeutral: Bool = false,
    userConfirmedURL: Bool = false
  ) async -> AcademicCalendarScrapeOutput? {
    await BackgroundServiceOnDemand.runReturning(id: "academic_calendar_import") {
      await importTermDatesImpl(
        persistence: persistence,
        calendarManager: calendarManager,
        writeChanges: writeChanges,
        urlOverride: urlOverride,
        departmentKey: departmentKey,
        hubPickerNeutral: hubPickerNeutral,
        userConfirmedURL: userConfirmedURL
      )
    }
  }

  private static func importTermDatesImpl(
    persistence: CollegePersistence,
    calendarManager: CalendarIntegrationManager,
    writeChanges: Bool = true,
    urlOverride: String? = nil,
    departmentKey: String? = nil,
    hubPickerNeutral: Bool = false,
    userConfirmedURL: Bool = false
  ) async -> AcademicCalendarScrapeOutput? {
    let resolution = await resolveEntryURL(persistence: persistence, urlOverride: urlOverride)
    guard let trimmedURL = resolution?.url.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmedURL.isEmpty else {
      return nil
    }

    let programProfile = AcademicCalendarProgramProfile.resolve(persistence: persistence)
    let levelScope = programProfile?.levelScope ?? AcademicCalendarProgramContext.levelScope(for: persistence)
    let schools = SchoolManifestCatalog.bundled()
    let universityName = persistence.getActiveUniversityName()?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "My University"
    let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(universityName) == .orderedSame })
    let schoolID = manifest?.id ?? universityName.lowercased().replacingOccurrences(of: " ", with: "_")
    let resolvedDepartmentKey = departmentKey ?? programProfile?.departmentKey ?? AcademicCalendarConfig.universityWideKey

    var config = AcademicCalendarStore.config(schoolID: schoolID, departmentKey: resolvedDepartmentKey)
      ?? AcademicCalendarConfig(
        schoolID: schoolID,
        name: manifest?.name ?? universityName,
        url: trimmedURL,
        chosenSubCalendarURL: nil,
        forcedMode: nil,
        timeZoneID: AcademicCalendarTimezone.resolve(manifest: manifest),
        levelScope: levelScope,
        importedScopes: [],
        departmentKey: resolvedDepartmentKey,
        departmentDisplayName: programProfile?.departmentDisplayName,
        schoolDisplayName: manifest?.name ?? universityName,
        discoverySource: resolution?.source,
        importStatus: .resolving
      )

    config.url = trimmedURL
    config.levelScope = levelScope
    config.schoolDisplayName = manifest?.name ?? universityName
    config.name = config.schoolDisplayName
    config.departmentDisplayName = programProfile?.departmentDisplayName ?? config.departmentDisplayName
    config.timeZoneID = AcademicCalendarTimezone.resolve(manifest: manifest)
    config.importedScopes = AcademicCalendarTermScope.importedScopes(
      persistence: persistence,
      level: levelScope
    )
    if let resolution {
      config.discoverySource = resolution.source
    }

    let output = await AcademicCalendarScrapeService.scrape(
      config: &config,
      reason: .manual,
      calendarManager: calendarManager,
      selectedSubCalendarURL: config.chosenSubCalendarURL,
      writeChanges: writeChanges,
      programProfile: programProfile,
      hubPickerNeutral: hubPickerNeutral,
      userConfirmedURL: userConfirmedURL
    )
    AcademicCalendarStore.upsertConfig(config)
    return output
  }

  static func importAdditionalDepartment(
    persistence: CollegePersistence,
    calendarManager: CalendarIntegrationManager,
    hubCandidate: AcademicCalendarSubCalendarCandidate,
    entryURL: String
  ) async -> AcademicCalendarScrapeOutput? {
    await BackgroundServiceOnDemand.runReturning(id: "academic_calendar_import") {
      await importAdditionalDepartmentImpl(
        persistence: persistence,
        calendarManager: calendarManager,
        hubCandidate: hubCandidate,
        entryURL: entryURL
      )
    }
  }

  private static func importAdditionalDepartmentImpl(
    persistence: CollegePersistence,
    calendarManager: CalendarIntegrationManager,
    hubCandidate: AcademicCalendarSubCalendarCandidate,
    entryURL: String
  ) async -> AcademicCalendarScrapeOutput? {
    guard AcademicCalendarStore.canAddDepartment(for: existingSchoolID(persistence: persistence) ?? "") else {
      return nil
    }
    let departmentKey = AcademicCalendarProgramProfile.departmentKey(from: hubCandidate.label)
    if AcademicCalendarStore.config(
      schoolID: existingSchoolID(persistence: persistence) ?? "",
      departmentKey: departmentKey
    ) != nil {
      return await importTermDates(
        persistence: persistence,
        calendarManager: calendarManager,
        urlOverride: entryURL,
        departmentKey: departmentKey,
        hubPickerNeutral: true,
        userConfirmedURL: true
      )
    }

    var config = await buildConfig(
      persistence: persistence,
      departmentKey: departmentKey,
      departmentDisplayName: AcademicCalendarProgramProfile.departmentDisplayName(
        from: hubCandidate.label,
        schoolName: persistence.getActiveUniversityName() ?? "University"
      ),
      url: entryURL
    )
    config.chosenSubCalendarURL = hubCandidate.url
    config.persistenceTier = .userConfirmed
    config.discoverySource = .hubPicker

    let profile = AcademicCalendarProgramProfile.resolve(persistence: persistence)
    return await AcademicCalendarScrapeService.scrape(
      config: &config,
      reason: .manual,
      calendarManager: calendarManager,
      selectedSubCalendarURL: hubCandidate.url,
      writeChanges: true,
      programProfile: profile,
      hubPickerNeutral: true,
      userConfirmedURL: true
    )
  }

  static func resolveCalendarURLSync(persistence: CollegePersistence) -> String? {
    guard let name = persistence.getActiveUniversityName()?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty else { return nil }

    let schools = SchoolManifestCatalog.bundled()
    let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    let schoolID = manifest?.id ?? name.lowercased().replacingOccurrences(of: " ", with: "_")

    if let cached = AcademicCalendarStore.primaryConfig(for: schoolID)?.url,
       !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return cached
    }
    return manifest?.academicCalendarURL
  }

  private static func resolveEntryURL(
    persistence: CollegePersistence,
    urlOverride: String?
  ) async -> AcademicCalendarDiscoveredEntry? {
    if let override = urlOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
      return AcademicCalendarDiscoveredEntry(
        url: override,
        source: .userPaste,
        confidence: 1.0,
        evidence: ["User provided URL"]
      )
    }

    guard let name = persistence.getActiveUniversityName()?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty else { return nil }

    let schools = SchoolManifestCatalog.bundled()
    let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    let schoolID = manifest?.id ?? name.lowercased().replacingOccurrences(of: " ", with: "_")

    if let cached = AcademicCalendarStore.primaryConfig(for: schoolID)?.url,
       !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return AcademicCalendarDiscoveredEntry(
        url: cached,
        source: .cached,
        confidence: 1.0,
        evidence: ["Cached validated URL"]
      )
    }

    if let manifestURL = manifest?.academicCalendarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
       !manifestURL.isEmpty {
      return AcademicCalendarDiscoveredEntry(
        url: manifestURL,
        source: .manifest,
        confidence: 1.0,
        evidence: ["Bundled manifest"]
      )
    }

    let discoverer = AcademicCalendarEntryDiscoverer(fetcher: AcademicCalendarFetchPort.shared)
    return await discoverer.discover(
      manifest: manifest,
      policyMetadata: persistence.activeSchoolPolicyMetadata(),
      universityName: name
    )
  }

  private static func existingConfig(persistence: CollegePersistence) -> AcademicCalendarConfig? {
    guard let schoolID = existingSchoolID(persistence: persistence) else { return nil }
    return AcademicCalendarStore.primaryConfig(for: schoolID)
  }

  private static func existingSchoolID(persistence: CollegePersistence) -> String? {
    AcademicCalendarSyncEligibility.activeSchoolID(persistence: persistence)
  }

  private static func buildConfig(
    persistence: CollegePersistence,
    departmentKey: String,
    departmentDisplayName: String,
    url: String
  ) async -> AcademicCalendarConfig {
    let schools = SchoolManifestCatalog.bundled()
    let universityName = persistence.getActiveUniversityName()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "My University"
    let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(universityName) == .orderedSame })
    let schoolID = manifest?.id ?? universityName.lowercased().replacingOccurrences(of: " ", with: "_")
    let levelScope = AcademicCalendarProgramContext.levelScope(for: persistence)
    return AcademicCalendarConfig(
      schoolID: schoolID,
      name: manifest?.name ?? universityName,
      url: url,
      timeZoneID: AcademicCalendarTimezone.resolve(manifest: manifest),
      levelScope: levelScope,
      importedScopes: AcademicCalendarTermScope.importedScopes(persistence: persistence, level: levelScope),
      departmentKey: departmentKey,
      departmentDisplayName: departmentDisplayName,
      schoolDisplayName: manifest?.name ?? universityName
    )
  }
}
