// AcademicCalendarManifestExport.swift
// Feature: Calendar
// Purpose: Export discovered calendar URLs for maintainer manifest review.

import Foundation

struct AcademicCalendarManifestExportEntry: Codable, Sendable, Equatable {
  var schoolID: String
  var schoolName: String
  var url: String
  var chosenSubCalendarURL: String?
  var discoverySource: String
  var validatedAt: Date
  var eventCount: Int
  var tier: String
}

enum AcademicCalendarManifestExportQueue {
  private static let queueKey = "calendar.discoveredCalendarURLs.v1"

  static func enqueue(from config: AcademicCalendarConfig) {
    guard config.persistenceTier == .shipCandidate || config.persistenceTier == .validatedAuto else { return }
    var entries = load()
    let entry = AcademicCalendarManifestExportEntry(
      schoolID: config.schoolID,
      schoolName: config.schoolDisplayName,
      url: config.url,
      chosenSubCalendarURL: config.chosenSubCalendarURL,
      discoverySource: config.discoverySource?.rawValue ?? "unknown",
      validatedAt: config.validatedAt ?? Date(),
      eventCount: config.lastSuccessfulEventCount,
      tier: config.persistenceTier?.rawValue ?? "validatedAuto"
    )
    entries.removeAll { $0.schoolID == config.schoolID && $0.url == config.url }
    entries.append(entry)
    save(entries)
    exportToDisk(entries)
  }

  static func load() -> [AcademicCalendarManifestExportEntry] {
    guard let data = UserDefaults.standard.data(forKey: queueKey),
          let decoded = try? JSONDecoder().decode([AcademicCalendarManifestExportEntry].self, from: data) else {
      return []
    }
    return decoded
  }

  private static func save(_ entries: [AcademicCalendarManifestExportEntry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: queueKey)
  }

  private static func exportToDisk(_ entries: [AcademicCalendarManifestExportEntry]) {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return
    }
    let dir = support.appendingPathComponent("College", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("discovered_calendar_urls.json")
    if let data = try? JSONEncoder().encode(entries) {
      try? data.write(to: file, options: .atomic)
    }
  }
}
