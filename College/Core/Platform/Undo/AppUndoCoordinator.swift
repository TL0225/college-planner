// AppUndoCoordinator.swift
// Feature: Core
// Purpose: Core module — AppUndoCoordinator.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Observation

/// Phase 7f: undo grouping for local store writes.
@MainActor
@Observable
final class AppUndoCoordinator {
    static let shared = AppUndoCoordinator()

    private var undoManager = UndoManager()

    private init() {}

    func performUndoable<T>(
        label: String,
        work: () throws -> T
    ) rethrows -> T {
        _ = label
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        return try work()
    }
}
