// CollegeSchemaLegacyStoreRepair.swift
// Feature: Core/Data
// Purpose: Re-stamp SwiftData stores whose coordinator version is no longer listed in
//          `CollegeSchemaMigrationPlan` (e.g. 1.2.0 / 1.5.0 / 1.7.0 checksum-only releases).

import Foundation
import SwiftData

@MainActor
enum CollegeSchemaLegacyStoreRepair {
  enum StorePartition: Sendable {
    case profile
    case catalog
    case unified

    var modelTypes: [any PersistentModel.Type] {
      switch self {
      case .profile: CollegeModelContainerFactory.profileModelTypes
      case .catalog: CollegeModelContainerFactory.catalogModelTypes
      case .unified: CollegeModelContainerFactory.unifiedModelTypes
      }
    }
  }

  /// Orphan schema stamps that must **not** appear in `CollegeSchemaMigrationPlan.schemas`
  /// (duplicate checksums) but may exist on disk from earlier app builds.
  private static let orphanVersions: [Schema.Version] = [
    Schema.Version(1, 7, 0),
    Schema.Version(1, 5, 0),
    Schema.Version(1, 2, 0),
  ]

  /// Re-stamp targets that **are** registered in `CollegeSchemaMigrationPlan.schemas`.
  private static let planVersions: [Schema.Version] = [
    CollegeSchemaV1_9.versionIdentifier,
    CollegeSchemaV1_8.versionIdentifier,
    CollegeSchemaV1_6.versionIdentifier,
    CollegeSchemaV1_4.versionIdentifier,
    CollegeSchemaV1_3.versionIdentifier,
    CollegeSchemaV1.versionIdentifier,
    CollegeSchemaV1_0.versionIdentifier,
  ]

  /// Opens a persistent store with staged migration, repairing orphan version stamps on 134504.
  static func openContainer(
    schema: Schema,
    migrationPlan: (any SchemaMigrationPlan.Type)?,
    url: URL,
    partition: StorePartition
  ) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url)
    let storeExists = FileManager.default.fileExists(atPath: url.path)

    // Existing stores: open without staged migration first. Core Data raises
    // `Duplicate version checksums across stages` via NSException when coordinator
    // metadata maps one checksum to multiple plan stages (not catchable in Swift).
    if storeExists,
       let direct = try? makeContainer(
         schema: schema,
         migrationPlan: nil,
         configuration: configuration
       ) {
      return direct
    }

    do {
      return try makeContainer(
        schema: schema,
        migrationPlan: migrationPlan,
        configuration: configuration
      )
    } catch {
      guard shouldAttemptRepair(for: error, storeURL: url) else { throw error }

      // Checksum drift or staged-migration metadata mismatch: open without staged migration first.
      if migrationPlan != nil,
         let direct = try? makeContainer(
           schema: schema,
           migrationPlan: nil,
           configuration: configuration
         ) {
        try? direct.mainContext.save()
        // Do not re-enter staged migration after a successful direct open — retrying can raise
        // `Duplicate version checksums across stages` via NSException (not catchable in Swift).
        return direct
      }

      guard repairStore(
        at: url,
        partition: partition,
        targetSchema: schema,
        configuration: configuration
      ) else { throw error }

      if let direct = try? makeContainer(
        schema: schema,
        migrationPlan: nil,
        configuration: configuration
      ) {
        return direct
      }
      return try makeContainer(
        schema: schema,
        migrationPlan: migrationPlan,
        configuration: configuration
      )
    }
  }

  // MARK: - Repair

  @discardableResult
  static func repairStore(
    at url: URL,
    partition: StorePartition,
    targetSchema: Schema,
    configuration: ModelConfiguration
  ) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }

    // Same version stamp (e.g. 1.3.0) but checksum drift after optional field additions.
    if openEphemeralContainer(schema: targetSchema, configuration: configuration) {
      return true
    }

    return restampOrphanStore(
      at: url,
      partition: partition,
      configuration: configuration
    )
  }

  @discardableResult
  static func restampOrphanStore(
    at url: URL,
    partition: StorePartition,
    configuration: ModelConfiguration? = nil
  ) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }

    let configuration = configuration ?? ModelConfiguration(url: url)
    let modelTypes = partition.modelTypes

    for orphan in orphanVersions {
      let orphanSchema = Schema(modelTypes, version: orphan)
      guard openEphemeralContainer(schema: orphanSchema, configuration: configuration) else {
        continue
      }

      let target = restampTarget(for: orphan)
      _ = openEphemeralContainer(
        schema: Schema(modelTypes, version: target),
        configuration: configuration
      )
      return true
    }

    for planVersion in planVersions {
      let planSchema = Schema(modelTypes, version: planVersion)
      if openEphemeralContainer(schema: planSchema, configuration: configuration) {
        return true
      }
    }

    return false
  }

  private static func restampTarget(for orphan: Schema.Version) -> Schema.Version {
    switch orphan {
    case Schema.Version(1, 7, 0):
      return CollegeSchemaV1_6.versionIdentifier
    case Schema.Version(1, 5, 0):
      return CollegeSchemaV1_4.versionIdentifier
    case Schema.Version(1, 2, 0):
      return CollegeSchemaV1.versionIdentifier
    default:
      return CollegeSchemaV1.versionIdentifier
    }
  }

  @discardableResult
  private static func openEphemeralContainer(
    schema: Schema,
    configuration: ModelConfiguration
  ) -> Bool {
    guard let container = try? ModelContainer(for: schema, configurations: configuration) else {
      return false
    }
    try? container.mainContext.save()
    return true
  }

  private static func makeContainer(
    schema: Schema,
    migrationPlan: (any SchemaMigrationPlan.Type)?,
    configuration: ModelConfiguration
  ) throws -> ModelContainer {
    if let migrationPlan {
      return try ModelContainer(
        for: schema,
        migrationPlan: migrationPlan,
        configurations: configuration
      )
    }
    return try ModelContainer(for: schema, configurations: configuration)
  }

  private static func shouldAttemptRepair(for error: Error, storeURL: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }

    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == 1_345_04 {
      return true
    }

    if let swiftDataError = error as? SwiftDataError,
       case .loadIssueModelContainer = swiftDataError {
      return true
    }

    let description = String(describing: error)
    return description.contains("unknown coordinator model version")
      || description.contains("unknown model version")
      || description.contains("Duplicate version checksums")
  }
}
