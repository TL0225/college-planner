// BackgroundModelContextPolicy.swift
// Feature: Core/Data
// Purpose: Rules for SwiftData reads/writes off the main actor.

import Foundation
import SwiftData

/// Contract for background `ModelContext` usage in College (Wave 4).
///
/// **Rules**
/// 1. Create contexts with `ModelContext(container)` on a detached task — never share the main-actor `profileContext`.
/// 2. One context per detached unit of work; do not pass live `@Model` instances across actor boundaries.
/// 3. Prefer read-only fetches in bridges; batch writes through repository helpers that own save/rollback.
/// 4. Return `Sendable` snapshots (value types) to the main actor — e.g. `CalendarEventSnapshot`, not `CalendarEvent`.
/// 5. Log fetch failures; avoid silent `try?` on required data paths.
/// 6. Keep container access on `@MainActor` (`AppDataStore.shared.profileContainer`) then hop to detached work.
enum BackgroundModelContextPolicy {
    /// Builds an isolated read context for the profile store container.
    static func makeReadContext(container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }
}
