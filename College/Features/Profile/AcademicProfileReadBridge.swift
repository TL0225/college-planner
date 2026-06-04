// AcademicProfileReadBridge.swift
// Feature: Profile
// Purpose: Profile module — AcademicProfileReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

@MainActor
enum AcademicProfileReadBridge {
    static func profiles(collegePersistence: CollegePersistence = .shared) -> [AcademicProfile] {
        (try? collegePersistence.profileRepository.fetchAcademicProfiles()) ?? []
    }

    /// Legacy shim removed (Phase 7f) — local store profiles only.
    static func entities(collegePersistence: CollegePersistence = .shared) -> [AcademicProfile] {
        profiles(collegePersistence: collegePersistence)
    }
}
