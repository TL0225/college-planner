// ProfileRepository+CareerSync.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+CareerSync.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    /// Legacy CD→SD sync removed (Phase 7f). Career writes go directly to local store.
    func syncCareerSnapshot(from manager: CollegePersistence) throws {
        _ = manager
    }
}