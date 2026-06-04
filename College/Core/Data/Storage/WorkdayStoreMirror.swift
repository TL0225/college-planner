// WorkdayStoreMirror.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — WorkdayStoreMirror.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Workday listings are written directly to local store via `CareerRepository` (Phase 7f).
@MainActor
enum WorkdayStoreMirror {
    static func syncPostings(companySlug: String? = nil, collegePersistence: CollegePersistence = .shared) {
        _ = companySlug
        _ = collegePersistence
    }
}