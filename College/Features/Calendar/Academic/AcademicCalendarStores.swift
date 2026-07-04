// AcademicCalendarStores.swift
// Feature: Calendar
// Purpose: UserDefaults persistence for academic calendar configs, ledger, and scrape logs.

import Foundation

enum AcademicCalendarStore {
  private static let configsKey = "calendar.academicConfigs.v1"
  private static let configsMigratedKey = "calendar.academicConfigs.migratedToV2"
  private static let ledgerPrefix = "calendar.academicLedger.v2."
  private static let legacyLedgerPrefix = "calendar.academicLedger.v1."
  private static let deletedKeysPrefix = "calendar.academicDeletedKeys.v2."
  private static let legacyDeletedKeysPrefix = "calendar.academicDeletedKeys.v1."
  private static let scrapeLogPrefix = "calendar.academicScrapeLog.v2."
  private static let legacyScrapeLogPrefix = "calendar.academicScrapeLog.v1."
  private static let maxLogEntries = 5
  private static let maxDepartmentsPerSchool = 5

  static func loadAllConfigs() -> [AcademicCalendarConfig] {
    guard let data = UserDefaults.standard.data(forKey: configsKey),
          let decoded = try? JSONDecoder().decode([AcademicCalendarConfig].self, from: data) else {
      return []
    }
    return decoded.sorted {
      if $0.schoolDisplayName != $1.schoolDisplayName {
        return $0.schoolDisplayName.localizedCaseInsensitiveCompare($1.schoolDisplayName) == .orderedAscending
      }
      return $0.departmentDisplayName.localizedCaseInsensitiveCompare($1.departmentDisplayName) == .orderedAscending
    }
  }

  static func saveAllConfigs(_ configs: [AcademicCalendarConfig]) {
    guard let data = try? JSONEncoder().encode(configs) else { return }
    UserDefaults.standard.set(data, forKey: configsKey)
  }

  static func config(configID: String) -> AcademicCalendarConfig? {
    loadAllConfigs().first { $0.configID == configID }
  }

  static func config(schoolID: String, departmentKey: String) -> AcademicCalendarConfig? {
    config(configID: AcademicCalendarConfig.makeConfigID(schoolID: schoolID, departmentKey: departmentKey))
  }

  static func primaryConfig(for schoolID: String) -> AcademicCalendarConfig? {
    let configs = configs(for: schoolID)
    return configs.first(where: { $0.departmentKey == AcademicCalendarConfig.universityWideKey }) ?? configs.first
  }

  static func configs(for schoolID: String) -> [AcademicCalendarConfig] {
    loadAllConfigs().filter { $0.schoolID == schoolID }
  }

  static func canAddDepartment(for schoolID: String) -> Bool {
    configs(for: schoolID).count < maxDepartmentsPerSchool
  }

  static func upsertConfig(_ config: AcademicCalendarConfig) {
    var all = loadAllConfigs()
    if let idx = all.firstIndex(where: { $0.configID == config.configID }) {
      all[idx] = config
    } else {
      all.append(config)
    }
    saveAllConfigs(all)
  }

  static func removeConfig(configID: String) {
    guard let config = config(configID: configID) else { return }
    var all = loadAllConfigs()
    all.removeAll { $0.configID == configID }
    saveAllConfigs(all)
    UserDefaults.standard.removeObject(forKey: ledgerKey(configID: configID))
    UserDefaults.standard.removeObject(forKey: deletedKeysKey(configID: configID))
    UserDefaults.standard.removeObject(forKey: scrapeLogKey(configID: configID))
    AcademicCalendarFingerprintCache.invalidate(schoolID: config.schoolID)
  }

  static func removeAllConfigs(for schoolID: String) {
    for config in configs(for: schoolID) {
      removeConfig(configID: config.configID)
    }
  }

  static func loadLedger(configID: String) -> [AcademicCalendarLedgerEntry] {
    if let data = UserDefaults.standard.data(forKey: ledgerKey(configID: configID)),
       let decoded = try? JSONDecoder().decode([AcademicCalendarLedgerEntry].self, from: data) {
      return decoded
    }
    if let migrated = migrateLegacyLedgerIfNeeded(configID: configID) {
      return migrated
    }
    return []
  }

  static func saveLedger(configID: String, entries: [AcademicCalendarLedgerEntry]) {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    UserDefaults.standard.set(data, forKey: ledgerKey(configID: configID))
  }

  static func loadDeletedKeys(configID: String) -> Set<String> {
    if let data = UserDefaults.standard.data(forKey: deletedKeysKey(configID: configID)),
       let decoded = try? JSONDecoder().decode([String].self, from: data) {
      return Set(decoded)
    }
    if let config = config(configID: configID) {
      if let legacy = UserDefaults.standard.data(forKey: legacyDeletedKeysKey(schoolID: config.schoolID)),
         let decoded = try? JSONDecoder().decode([String].self, from: legacy) {
        return Set(decoded)
      }
    }
    return []
  }

  static func saveDeletedKeys(configID: String, keys: Set<String>) {
    let data = try? JSONEncoder().encode(Array(keys))
    UserDefaults.standard.set(data, forKey: deletedKeysKey(configID: configID))
  }

  static func appendDeletedKey(configID: String, identityKey: String) {
    var keys = loadDeletedKeys(configID: configID)
    keys.insert(identityKey)
    saveDeletedKeys(configID: configID, keys: keys)
  }

  static func clearDeletedKeys(configID: String) {
    saveDeletedKeys(configID: configID, keys: [])
  }

  static func loadScrapeLog(configID: String) -> [AcademicCalendarScrapeLogEntry] {
    if let data = UserDefaults.standard.data(forKey: scrapeLogKey(configID: configID)),
       let decoded = try? JSONDecoder().decode([AcademicCalendarScrapeLogEntry].self, from: data) {
      return decoded
    }
    if let config = config(configID: configID),
       let legacy = UserDefaults.standard.data(forKey: legacyScrapeLogKey(schoolID: config.schoolID)),
       let decoded = try? JSONDecoder().decode([AcademicCalendarScrapeLogEntry].self, from: legacy) {
      return decoded
    }
    return []
  }

  static func appendScrapeLog(configID: String, entry: AcademicCalendarScrapeLogEntry) {
    var log = loadScrapeLog(configID: configID)
    log.insert(entry, at: 0)
    if log.count > maxLogEntries {
      log = Array(log.prefix(maxLogEntries))
    }
    guard let data = try? JSONEncoder().encode(log) else { return }
    UserDefaults.standard.set(data, forKey: scrapeLogKey(configID: configID))
  }

  @MainActor
  static func runMigrationIfNeeded(calendarManager: CalendarIntegrationManager? = nil) {
    guard !UserDefaults.standard.bool(forKey: configsMigratedKey) else { return }
    var configs = loadAllConfigs()
    var changed = false
    for index in configs.indices {
      if configs[index].departmentKey.isEmpty {
        configs[index].departmentKey = AcademicCalendarConfig.universityWideKey
        changed = true
      }
      if configs[index].configID.isEmpty {
        configs[index].configID = AcademicCalendarConfig.makeConfigID(
          schoolID: configs[index].schoolID,
          departmentKey: configs[index].departmentKey
        )
        changed = true
      }
      if configs[index].schoolDisplayName.isEmpty {
        configs[index].schoolDisplayName = configs[index].name
        changed = true
      }
    }
    if changed { saveAllConfigs(configs) }

    for config in configs {
      _ = migrateLegacyLedgerIfNeeded(configID: config.configID)
      if let calendarManager {
        AcademicCalendarIntegration.registerCalendarIfNeeded(config: config, calendarManager: calendarManager)
      }
    }
    UserDefaults.standard.set(true, forKey: configsMigratedKey)
  }

  // MARK: - Legacy compatibility

  static func config(for schoolID: String) -> AcademicCalendarConfig? {
    primaryConfig(for: schoolID)
  }

  static func removeConfig(schoolID: String) {
    removeAllConfigs(for: schoolID)
  }

  static func loadLedger(schoolID: String) -> [AcademicCalendarLedgerEntry] {
    guard let config = primaryConfig(for: schoolID) else { return [] }
    return loadLedger(configID: config.configID)
  }

  static func saveLedger(schoolID: String, entries: [AcademicCalendarLedgerEntry]) {
    guard let config = primaryConfig(for: schoolID) else { return }
    saveLedger(configID: config.configID, entries: entries)
  }

  static func loadDeletedKeys(schoolID: String) -> Set<String> {
    guard let config = primaryConfig(for: schoolID) else { return [] }
    return loadDeletedKeys(configID: config.configID)
  }

  static func saveDeletedKeys(schoolID: String, keys: Set<String>) {
    guard let config = primaryConfig(for: schoolID) else { return }
    saveDeletedKeys(configID: config.configID, keys: keys)
  }

  static func appendDeletedKey(schoolID: String, identityKey: String) {
    guard let config = primaryConfig(for: schoolID) else { return }
    appendDeletedKey(configID: config.configID, identityKey: identityKey)
  }

  static func clearDeletedKeys(schoolID: String) {
    guard let config = primaryConfig(for: schoolID) else { return }
    clearDeletedKeys(configID: config.configID)
  }

  static func loadScrapeLog(schoolID: String) -> [AcademicCalendarScrapeLogEntry] {
    guard let config = primaryConfig(for: schoolID) else { return [] }
    return loadScrapeLog(configID: config.configID)
  }

  static func appendScrapeLog(schoolID: String, entry: AcademicCalendarScrapeLogEntry) {
    guard let config = primaryConfig(for: schoolID) else { return }
    appendScrapeLog(configID: config.configID, entry: entry)
  }

  private static func migrateLegacyLedgerIfNeeded(configID: String) -> [AcademicCalendarLedgerEntry]? {
    guard let config = config(configID: configID) else { return nil }
    let legacyKey = legacyLedgerKey(schoolID: config.schoolID)
    guard let data = UserDefaults.standard.data(forKey: legacyKey),
          let decoded = try? JSONDecoder().decode([AcademicCalendarLedgerEntry].self, from: data) else {
      return nil
    }
    saveLedger(configID: configID, entries: decoded)
    UserDefaults.standard.removeObject(forKey: legacyKey)
    return decoded
  }

  private static func ledgerKey(configID: String) -> String { ledgerPrefix + configID }
  private static func legacyLedgerKey(schoolID: String) -> String { legacyLedgerPrefix + schoolID }
  private static func deletedKeysKey(configID: String) -> String { deletedKeysPrefix + configID }
  private static func legacyDeletedKeysKey(schoolID: String) -> String { legacyDeletedKeysPrefix + schoolID }
  private static func scrapeLogKey(configID: String) -> String { scrapeLogPrefix + configID }
  private static func legacyScrapeLogKey(schoolID: String) -> String { legacyScrapeLogPrefix + schoolID }
}

import CollegeCalendar
