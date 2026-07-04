// AppUndoCoordinator.swift
// Feature: Core
// Purpose: Core module — AppUndoCoordinator.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Observation

/// Phase 7f/10: app-wide undo support for local store writes.
///
/// Registers reversible actions against the window's `UndoManager` (supplied
/// from the SwiftUI environment) so that ⌘Z / ⌘⇧Z work in editing contexts.
@MainActor
@Observable
final class AppUndoCoordinator {
    static let shared = AppUndoCoordinator()

    /// The active window's undo manager, connected from the SwiftUI environment.
    @ObservationIgnored weak var undoManager: UndoManager?

    private init() {}

    /// Connects the coordinator to the environment-provided undo manager.
    func connect(_ manager: UndoManager?) {
        undoManager = manager
    }

    /// Executes `forward` immediately and registers `backward` as its inverse.
    ///
    /// When the user triggers Undo, `backward` runs and `forward` is re-registered
    /// as the redo, giving full undo/redo cycling for fully reversible operations.
    func performUndoable(
        label: String,
        forward: @escaping () -> Void,
        backward: @escaping () -> Void
    ) {
        forward()
        guard let undoManager else { return }
        undoManager.setActionName(label)
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.performUndoable(label: label, forward: backward, backward: forward)
        }
    }

    /// Grouping helper retained for call sites that only need a single
    /// transactional block (no automatic inverse).
    func performUndoable<T>(
        label: String,
        work: () throws -> T
    ) rethrows -> T {
        guard let undoManager else { return try work() }
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        undoManager.setActionName(label)
        return try work()
    }
}
