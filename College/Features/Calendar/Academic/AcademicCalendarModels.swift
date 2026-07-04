// AcademicCalendarModels.swift
// Feature: Calendar
// Purpose: Models for academic calendar scraping, reconciliation, and sync.

import Foundation

enum AcademicCalendarForcedMode: String, Codable, CaseIterable, Sendable {
  case auto
  case ics
  case hub
  case scrape

  var displayName: String {
    switch self {
    case .auto: return "Auto"
    case .ics: return "ICS Feed"
    case .hub: return "Hub Picker"
    case .scrape: return "Scrape Page"
    }
  }
}

enum AcademicCalendarPageKind: String, Sendable {
  case hasICSFeed
  case indexHub
  case calendar
}

enum AcademicCalendarScrapePath: String, Codable, Sendable {
  case ics
  case hub
  case scrape
  case skippedUnchanged
}

enum AcademicCalendarEventStatus: String, Codable, Sendable {
  case confirmed
  case tentative
  case cancelled
}

enum AcademicCalendarLevelScope: String, Codable, CaseIterable, Sendable {
  case all
  case undergrad
  case grad

  var displayName: String {
    switch self {
    case .all: return "All"
    case .undergrad: return "Undergraduate"
    case .grad: return "Graduate"
    }
  }
}

enum AcademicCalendarDiscoverySource: String, Codable, Sendable {
  case manifest
  case cached
  case registrar
  case userPaste
  case hubPicker
  case validatedAuto
}

enum AcademicCalendarPersistenceTier: String, Codable, Sendable {
  case ephemeral
  case userConfirmed
  case validatedAuto
  case shipCandidate
}

enum AcademicCalendarImportStatus: String, Codable, Sendable {
  case notStarted
  case discovering
  case resolving
  case needsChoice
  case previewReady
  case imported
  case needsAttention
  case needsHelp
}

struct AcademicCalendarImportedScope: Codable, Hashable, Sendable {
  var term: String
  var year: Int
  var level: AcademicCalendarLevelScope
}

struct AcademicCalendarConfig: Codable, Identifiable, Sendable {
  static let universityWideKey = "university_wide"
  static let configsSchemaVersion = 2

  var configID: String
  var schoolID: String
  var departmentKey: String
  var departmentDisplayName: String
  var schoolDisplayName: String
  /// Legacy alias for school display name.
  var name: String
  var url: String
  var chosenSubCalendarURL: String?
  var forcedMode: AcademicCalendarForcedMode?
  var timeZoneID: String
  var levelScope: AcademicCalendarLevelScope
  var importedScopes: [AcademicCalendarImportedScope]
  var etag: String?
  var lastContentHash: String?
  var lastSuccessfulEventCount: Int
  var lastAttemptedAt: Date?
  var lastSuccessfulAt: Date?
  var lastError: String?
  var discoverySource: AcademicCalendarDiscoverySource?
  var validatedAt: Date?
  var persistenceTier: AcademicCalendarPersistenceTier?
  var importStatus: AcademicCalendarImportStatus?
  var profileFingerprint: String?
  var hubCandidatesCachedAt: Date?
  var cachedHubCandidates: [AcademicCalendarSubCalendarCandidate]?

  var id: String { configID }

  static func makeConfigID(schoolID: String, departmentKey: String) -> String {
    "\(schoolID):\(departmentKey)"
  }

  static func providerSource(for schoolID: String) -> String {
    providerSource(schoolID: schoolID, departmentKey: universityWideKey)
  }

  static func providerSource(schoolID: String, departmentKey: String) -> String {
    "academic:\(schoolID):\(departmentKey)"
  }

  static func parseProviderSource(_ source: String) -> (schoolID: String, departmentKey: String)? {
    guard source.hasPrefix("academic:") else { return nil }
    let remainder = String(source.dropFirst("academic:".count))
    if let colon = remainder.lastIndex(of: ":") {
      let school = String(remainder[..<colon])
      let dept = String(remainder[remainder.index(after: colon)...])
      guard !school.isEmpty, !dept.isEmpty else { return nil }
      return (school, dept)
    }
    guard !remainder.isEmpty else { return nil }
    return (remainder, universityWideKey)
  }

  var providerSource: String { Self.providerSource(schoolID: schoolID, departmentKey: departmentKey) }

  var toggleID: String { "Academic:\(schoolID):\(departmentKey)" }

  var calendarDisplayName: String { departmentDisplayName }

  init(
    schoolID: String,
    name: String,
    url: String,
    chosenSubCalendarURL: String? = nil,
    forcedMode: AcademicCalendarForcedMode? = nil,
    timeZoneID: String,
    levelScope: AcademicCalendarLevelScope,
    importedScopes: [AcademicCalendarImportedScope],
    etag: String? = nil,
    lastContentHash: String? = nil,
    lastSuccessfulEventCount: Int = 0,
    lastAttemptedAt: Date? = nil,
    lastSuccessfulAt: Date? = nil,
    lastError: String? = nil,
    departmentKey: String = universityWideKey,
    departmentDisplayName: String? = nil,
    schoolDisplayName: String? = nil,
    discoverySource: AcademicCalendarDiscoverySource? = nil,
    validatedAt: Date? = nil,
    persistenceTier: AcademicCalendarPersistenceTier? = nil,
    importStatus: AcademicCalendarImportStatus? = nil,
    profileFingerprint: String? = nil,
    hubCandidatesCachedAt: Date? = nil,
    cachedHubCandidates: [AcademicCalendarSubCalendarCandidate]? = nil
  ) {
    self.schoolID = schoolID
    self.departmentKey = departmentKey
    self.configID = Self.makeConfigID(schoolID: schoolID, departmentKey: departmentKey)
    self.schoolDisplayName = schoolDisplayName ?? name
    self.name = name
    self.departmentDisplayName = departmentDisplayName ?? "\(name) Term Dates"
    self.url = url
    self.chosenSubCalendarURL = chosenSubCalendarURL
    self.forcedMode = forcedMode
    self.timeZoneID = timeZoneID
    self.levelScope = levelScope
    self.importedScopes = importedScopes
    self.etag = etag
    self.lastContentHash = lastContentHash
    self.lastSuccessfulEventCount = lastSuccessfulEventCount
    self.lastAttemptedAt = lastAttemptedAt
    self.lastSuccessfulAt = lastSuccessfulAt
    self.lastError = lastError
    self.discoverySource = discoverySource
    self.validatedAt = validatedAt
    self.persistenceTier = persistenceTier
    self.importStatus = importStatus
    self.profileFingerprint = profileFingerprint
    self.hubCandidatesCachedAt = hubCandidatesCachedAt
    self.cachedHubCandidates = cachedHubCandidates
  }

  enum CodingKeys: String, CodingKey {
    case configID, schoolID, departmentKey, departmentDisplayName, schoolDisplayName, name
    case url, chosenSubCalendarURL, forcedMode, timeZoneID, levelScope, importedScopes
    case etag, lastContentHash, lastSuccessfulEventCount, lastAttemptedAt, lastSuccessfulAt, lastError
    case discoverySource, validatedAt, persistenceTier, importStatus, profileFingerprint
    case hubCandidatesCachedAt, cachedHubCandidates
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schoolID = try container.decode(String.self, forKey: .schoolID)
    departmentKey = try container.decodeIfPresent(String.self, forKey: .departmentKey) ?? Self.universityWideKey
    configID = try container.decodeIfPresent(String.self, forKey: .configID)
      ?? Self.makeConfigID(schoolID: schoolID, departmentKey: departmentKey)
    name = try container.decode(String.self, forKey: .name)
    schoolDisplayName = try container.decodeIfPresent(String.self, forKey: .schoolDisplayName) ?? name
    departmentDisplayName = try container.decodeIfPresent(String.self, forKey: .departmentDisplayName)
      ?? "\(name) Term Dates"
    url = try container.decode(String.self, forKey: .url)
    chosenSubCalendarURL = try container.decodeIfPresent(String.self, forKey: .chosenSubCalendarURL)
    forcedMode = try container.decodeIfPresent(AcademicCalendarForcedMode.self, forKey: .forcedMode)
    timeZoneID = try container.decode(String.self, forKey: .timeZoneID)
    levelScope = try container.decode(AcademicCalendarLevelScope.self, forKey: .levelScope)
    importedScopes = try container.decode([AcademicCalendarImportedScope].self, forKey: .importedScopes)
    etag = try container.decodeIfPresent(String.self, forKey: .etag)
    lastContentHash = try container.decodeIfPresent(String.self, forKey: .lastContentHash)
    lastSuccessfulEventCount = try container.decodeIfPresent(Int.self, forKey: .lastSuccessfulEventCount) ?? 0
    lastAttemptedAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptedAt)
    lastSuccessfulAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt)
    lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    discoverySource = try container.decodeIfPresent(AcademicCalendarDiscoverySource.self, forKey: .discoverySource)
    validatedAt = try container.decodeIfPresent(Date.self, forKey: .validatedAt)
    persistenceTier = try container.decodeIfPresent(AcademicCalendarPersistenceTier.self, forKey: .persistenceTier)
    importStatus = try container.decodeIfPresent(AcademicCalendarImportStatus.self, forKey: .importStatus)
    profileFingerprint = try container.decodeIfPresent(String.self, forKey: .profileFingerprint)
    hubCandidatesCachedAt = try container.decodeIfPresent(Date.self, forKey: .hubCandidatesCachedAt)
    cachedHubCandidates = try container.decodeIfPresent([AcademicCalendarSubCalendarCandidate].self, forKey: .cachedHubCandidates)
  }
}

struct AcademicCalendarImportedSnapshot: Codable, Equatable, Sendable {
  var title: String
  var startDate: Date
  var endDate: Date
  var allDay: Bool
  var notes: String?
  var status: AcademicCalendarEventStatus
}

struct AcademicCalendarLedgerEntry: Codable, Identifiable, Sendable {
  var id: String { identityKey }
  var localID: UUID
  var identityKey: String
  var identitySignature: String
  var scopeKey: String
  var importedSnapshot: AcademicCalendarImportedSnapshot
  var status: AcademicCalendarEventStatus
  var confidence: Double
  var promptVersion: Int
  var userModified: Bool
  var lastSeenScrapeID: UUID?
}

struct AcademicCalendarScrapeLogEntry: Codable, Identifiable, Sendable {
  var id: UUID
  var timestamp: Date
  var reason: String
  var path: AcademicCalendarScrapePath
  var added: Int
  var changed: Int
  var removed: Int
  var skipped: Int
  var error: String?
}

struct AcademicCalendarSubCalendarCandidate: Identifiable, Hashable, Codable, Sendable {
  var id: String { url }
  var label: String
  var url: String
}

struct AcademicCalendarDiscoveredEntry: Sendable, Equatable {
  var url: String
  var source: AcademicCalendarDiscoverySource
  var confidence: Double
  var evidence: [String]
}

struct AcademicCalendarParsedEvent: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var startDate: Date
  var endDate: Date
  var allDay: Bool
  var status: AcademicCalendarEventStatus
  var term: String
  var year: Int
  var level: AcademicCalendarLevelScope
  var confidence: Double
  var scopeKey: String
  var identityKey: String
  var identitySignature: String
  var providerEventId: String?
  var notes: String?
  var isLowConfidence: Bool
}

enum AcademicCalendarSyncChangeKind: String, Sendable {
  case added
  case changed
  case removed
  case suppressed
  case moved
  case upstreamRemovedUpdate
  case userModifiedConflict
}

struct AcademicCalendarSyncChange: Identifiable, Sendable {
  var id: String
  var kind: AcademicCalendarSyncChangeKind
  var title: String
  var detail: String?
  var event: AcademicCalendarParsedEvent?
  var fromScope: String?
  var toScope: String?
}

struct AcademicCalendarSyncResult: Sendable {
  var scrapeID: UUID
  var added: Int
  var changed: Int
  var removed: Int
  var skipped: Int
  var moved: Int
  var changes: [AcademicCalendarSyncChange]
  var parsedEvents: [AcademicCalendarParsedEvent]
  var path: AcademicCalendarScrapePath
  var error: String?

  var totalDelta: Int { added + changed + removed + moved }

  static let empty = AcademicCalendarSyncResult(
    scrapeID: UUID(),
    added: 0,
    changed: 0,
    removed: 0,
    skipped: 0,
    moved: 0,
    changes: [],
    parsedEvents: [],
    path: .skippedUnchanged,
    error: nil
  )
}

enum AcademicCalendarPrompt {
  static let version = 1
}
