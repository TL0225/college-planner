// MLXTaskQueue.swift
// Feature: Catalog
// Purpose: Catalog module — MLXTaskQueueError.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension Notification.Name {
    /// Posted on the main queue when the number of tasks waiting for the MLX serial gate changes.
    /// `userInfo["depth"]` is an `Int` count of pending waiters (0 when idle or only the running task holds the lock).
    static let mlxTaskQueueWaitingDepthChanged = Notification.Name("mlxTaskQueueWaitingDepthChanged")
}

enum MLXTaskQueueError: Error, Sendable {
    case backlogExceeded
}

/// Serial gate for all MLX / Metal-backed work (JSON LLM inference, embedding models, weight loads).
///
/// **Concurrency audit (single-flight):** all `ChatSession` / `loadModelContainer` work from the app must enter through this actor. Verified paths:
/// - ``LocalLLMRunner`` (all `generateJSON*` / preWarm) → ``run``.
/// - ``CatalogMLXEmbedService`` / sentence embeddings → ``run``.
/// - ``CatalogEmbeddingRuntime`` → ``run``.
///
/// Do not add parallel MLX inference that bypasses this queue; extend this actor if a new Metal workload must serialize with the JSON worker.
enum MLXTaskPriority: Sendable, Comparable {
    /// User-facing assistant turns and any UI-blocking generation.
    case userInitiated
    /// Background catalog indexing / pre-warm; yields when a user job is waiting.
    case utility

    static func < (lhs: MLXTaskPriority, rhs: MLXTaskPriority) -> Bool {
        // utility < userInitiated so `.sort { $0 > $1 }` puts user first.
        switch (lhs, rhs) {
        case (.utility, .userInitiated): return true
        case (.userInitiated, .utility): return false
        default: return false
        }
    }

    var taskPriority: TaskPriority {
        switch self {
        case .userInitiated: return .userInitiated
        case .utility: return .utility
        }
    }
}

actor MLXTaskQueue {
    static let shared = MLXTaskQueue()

    private let maxPending = 32
    private var locked = false
    private var waiters: [(prio: MLXTaskPriority, cont: CheckedContinuation<Void, Never>)] = []

    /// Runs `operation` exclusively against other MLX work. Higher `priority` waiters are resumed first.
    func run<R: Sendable>(
        priority: MLXTaskPriority,
        operation: @Sendable @escaping () async throws -> R
    ) async throws -> R {
        try await acquire(priority: priority)
        defer { release() }
        return try await operation()
    }

    private func acquire(priority: MLXTaskPriority) async throws {
        if !locked {
            locked = true
            publishWaitingDepth()
            return
        }
        guard waiters.count < maxPending else {
            let depth = waiters.count
            Task { @MainActor in
                DebugLogger.shared.log(
                    "MLXTaskQueue backlogExceeded — too many pending MLX waiters (\(depth)). Categorize callers to reduce concurrent `run` spam.",
                    category: .intelligence,
                    level: .error
                )
            }
            throw MLXTaskQueueError.backlogExceeded
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append((priority, cont))
            waiters.sort { $0.prio > $1.prio }
            publishWaitingDepth()
        }
        publishWaitingDepth()
    }

    private func release() {
        if let (_, cont) = waiters.first {
            waiters.removeFirst()
            publishWaitingDepth()
            cont.resume()
        } else {
            locked = false
            publishWaitingDepth()
        }
    }

    private func publishWaitingDepth() {
        let depth = waiters.count
#if DEBUG
        if depth > 0 {
            Task { @MainActor in
                DebugLogger.shared.log(
                    "MLXTaskQueue waiter depth=\(depth) (MLX work queued on serial gate)",
                    category: .intelligence,
                    level: .trace
                )
            }
        }
#endif
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .mlxTaskQueueWaitingDepthChanged,
                object: nil,
                userInfo: ["depth": depth]
            )
        }
    }
}
