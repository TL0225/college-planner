// LaunchStartupBudget.swift
// Feature: App
// Purpose: App module — Lane.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Limits concurrent deferred startup work so heavy database and file I/O do not pile up after first frame.
///
/// At most one task per lane runs at a time; `.database` and `.fileIO` lanes can each hold one task,
/// so you get up to **two** concurrent deferred operations (one DB-shaped, one I/O-shaped).
actor LaunchStartupBudget {
    enum Lane: Sendable {
        case database
        case fileIO
    }

    static let shared = LaunchStartupBudget()

    private var databaseLeases = 0
    private var fileIOLeases = 0
    private let maxDatabaseConcurrent = 1
    private let maxFileIOConcurrent = 2

    func run<T: Sendable>(
        lane: Lane,
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        await acquire(lane)
        defer { release(lane) }
        return try await operation()
    }

    private func acquire(_ lane: Lane) async {
        switch lane {
        case .database:
            while databaseLeases >= maxDatabaseConcurrent {
                await Task.yield()
            }
            databaseLeases += 1
        case .fileIO:
            while fileIOLeases >= maxFileIOConcurrent {
                await Task.yield()
            }
            fileIOLeases += 1
        }
    }

    private func release(_ lane: Lane) {
        switch lane {
        case .database:
            databaseLeases = max(0, databaseLeases - 1)
        case .fileIO:
            fileIOLeases = max(0, fileIOLeases - 1)
        }
    }
}
