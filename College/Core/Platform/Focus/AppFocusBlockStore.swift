// AppFocusBlockStore.swift
// Feature: Core
// Purpose: Core module — FocusBlock.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation
import SwiftData

/// Phase 9: focus blocks persisted in the profile local store store.
struct FocusBlock: Identifiable, Codable, Sendable {
    var id: UUID
    var title: String
    var startHour: Int
    var endHour: Int
    var weekdays: [Int]
}

@MainActor
@Observable
final class AppFocusBlockStore {
    static let shared = AppFocusBlockStore()

    private static let legacyUserDefaultsKey = "calendar.focusBlocks"
    private static let migrationFlagKey = "calendar.focusBlocks.localStoreImported"

    private(set) var blocks: [FocusBlock] = []

    private init() {
        restore()
    }

    func add(_ block: FocusBlock) {
        blocks.append(block)
        persist()
    }

    func remove(id: UUID) {
        blocks.removeAll { $0.id == id }
        persist()
    }

    private var profileRepository: ProfileRepository {
        ProfileRepository(context: AppDataStore.shared.profileContext)
    }

    private func persist() {
        do {
            try profileRepository.replaceFocusBlocks(blocks)
        } catch {
            AppLogger.shared.error("AppFocusBlockStore: failed to save focus blocks: \(error)")
        }
    }

    private func restore() {
        importLegacyUserDefaultsIfNeeded()
        do {
            let records = try profileRepository.fetchFocusBlocks()
            blocks = records.compactMap { $0.toFocusBlock() }
        } catch {
            AppLogger.shared.error("AppFocusBlockStore: failed to load focus blocks: \(error)")
            blocks = []
        }
    }

    /// One-time import from pre-local store UserDefaults storage.
    private func importLegacyUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migrationFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.migrationFlagKey) }

        guard let data = UserDefaults.standard.data(forKey: Self.legacyUserDefaultsKey),
              let decoded = try? JSONDecoder().decode([FocusBlock].self, from: data),
              !decoded.isEmpty
        else { return }

        do {
            try profileRepository.replaceFocusBlocks(decoded)
            UserDefaults.standard.removeObject(forKey: Self.legacyUserDefaultsKey)
        } catch {
            AppLogger.shared.error("AppFocusBlockStore: legacy import failed: \(error)")
        }
    }
}
