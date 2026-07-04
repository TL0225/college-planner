// VaultImportSerialQueue.swift
// Feature: Core
// Purpose: Serializes vault imports so concurrent uploads do not interleave writes.

import Foundation

actor VaultImportSerialQueue {
    static let shared = VaultImportSerialQueue()

    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return try await task.value
    }
}
