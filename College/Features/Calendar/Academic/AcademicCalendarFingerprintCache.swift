// AcademicCalendarFingerprintCache.swift
// Feature: Calendar
// Purpose: Cache validated sub-calendar URLs per program fingerprint.

import Foundation

enum AcademicCalendarFingerprintCache {
  private static let cacheKey = "calendar.academicFingerprintCache.v1"
  private static let hubCacheKey = "calendar.academicHubCache.v1"
  private static let hubCacheTTL: TimeInterval = 7 * 24 * 60 * 60

  struct Entry: Codable, Sendable, Equatable {
    var schoolID: String
    var fingerprint: String
    var chosenSubCalendarURL: String
    var validatedAt: Date
    var confidence: Double
  }

  struct HubCacheEntry: Codable, Sendable, Equatable {
    var schoolID: String
    var candidates: [AcademicCalendarSubCalendarCandidate]
    var cachedAt: Date
  }

  static func fingerprint(for profile: AcademicCalendarProgramProfile, schoolID: String) -> String {
    let seed = "\(schoolID)|\(profile.fingerprintSeed)"
    return String(seed.hashValue)
  }

  static func lookup(schoolID: String, fingerprint: String) -> Entry? {
    loadEntries().first { $0.schoolID == schoolID && $0.fingerprint == fingerprint }
  }

  static func store(schoolID: String, fingerprint: String, chosenSubCalendarURL: String, confidence: Double) {
    var entries = loadEntries().filter { !($0.schoolID == schoolID && $0.fingerprint == fingerprint) }
    entries.append(
      Entry(
        schoolID: schoolID,
        fingerprint: fingerprint,
        chosenSubCalendarURL: chosenSubCalendarURL,
        validatedAt: Date(),
        confidence: confidence
      )
    )
    saveEntries(entries)
  }

  static func invalidate(schoolID: String) {
    let entries = loadEntries().filter { $0.schoolID != schoolID }
    saveEntries(entries)
  }

  static func invalidateAll() {
    UserDefaults.standard.removeObject(forKey: cacheKey)
  }

  static func hubCandidates(for schoolID: String) -> [AcademicCalendarSubCalendarCandidate]? {
    guard let entry = loadHubEntries().first(where: { $0.schoolID == schoolID }),
          Date().timeIntervalSince(entry.cachedAt) < hubCacheTTL else {
      return nil
    }
    return entry.candidates
  }

  static func storeHubCandidates(schoolID: String, candidates: [AcademicCalendarSubCalendarCandidate]) {
    var entries = loadHubEntries().filter { $0.schoolID != schoolID }
    entries.append(HubCacheEntry(schoolID: schoolID, candidates: candidates, cachedAt: Date()))
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: hubCacheKey)
  }

  private static func loadEntries() -> [Entry] {
    guard let data = UserDefaults.standard.data(forKey: cacheKey),
          let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
      return []
    }
    return decoded
  }

  private static func saveEntries(_ entries: [Entry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: cacheKey)
  }

  private static func loadHubEntries() -> [HubCacheEntry] {
    guard let data = UserDefaults.standard.data(forKey: hubCacheKey),
          let decoded = try? JSONDecoder().decode([HubCacheEntry].self, from: data) else {
      return []
    }
    return decoded
  }
}
