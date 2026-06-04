// ProfileRepository+VaultSync.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+VaultSync.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    /// Legacy CD→SD sync removed (Phase 7f). Vault writes go directly to local store.
    func syncVaultSnapshot(from manager: CollegePersistence) throws {
        _ = manager
    }
}