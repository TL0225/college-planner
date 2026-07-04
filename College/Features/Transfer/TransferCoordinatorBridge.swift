// TransferCoordinatorBridge.swift
// Feature: Transfer
// Purpose: Wires window-scoped TransferCoordinator into background service manifest.

import Foundation

@MainActor
enum TransferCoordinatorBridge {
    private(set) static weak var coordinator: TransferCoordinator?

    static func wire(_ coordinator: TransferCoordinator) {
        self.coordinator = coordinator
    }

    static func bootstrapIfNeeded() {
        coordinator?.bootstrap()
    }
}
