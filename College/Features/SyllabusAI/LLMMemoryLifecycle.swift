// LLMMemoryLifecycle.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — LLMMemoryLifecycle.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Idle unload coordinator for MLX-backed JSON worker (Syllabus, catalog, assistant fallback — not FM).
@MainActor
final class LLMMemoryLifecycle {
    static let shared = LLMMemoryLifecycle()

    static let idleTimeoutSecondsKey = "assistant.llm.idleTimeoutSeconds"
    static let freeMemoryBetweenSessionsKey = "assistant.llm.freeMemoryBetweenSessions"

    private var idleTask: Task<Void, Never>?
    private(set) var lastIdleReleaseAt: Date?

    var idleTimeout: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.idleTimeoutSecondsKey)
        return stored > 0 ? stored : 120
    }

    var freeMemoryBetweenSessionsEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.freeMemoryBetweenSessionsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.freeMemoryBetweenSessionsKey)
    }

    func touch() {
        guard freeMemoryBetweenSessionsEnabled else { return }
        scheduleIdleRelease()
    }

    func cancelIdleRelease() {
        idleTask?.cancel()
        idleTask = nil
    }

    func releaseNow() {
        cancelIdleRelease()
        Task {
            let signpost = PerformanceSignposts.beginLLMUnload(reason: "releaseNow")
            await LocalLLMRunner.shared.releaseModel()
            PerformanceSignposts.endLLMUnload(signpost)
            lastIdleReleaseAt = Date()
        }
    }

    func scheduleIdleRelease() {
        cancelIdleRelease()
        let seconds = idleTimeout
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let signpost = PerformanceSignposts.beginLLMUnload(reason: "idleTimeout")
            await LocalLLMRunner.shared.releaseModel()
            PerformanceSignposts.endLLMUnload(signpost)
            lastIdleReleaseAt = Date()
            DebugLogger.shared.log(
                "LLMMemoryLifecycle: idle release after \(Int(seconds))s",
                category: .system,
                level: .info
            )
        }
    }
}

extension Notification.Name {
    static let llmModelDidLoad = Notification.Name("college.llmModelDidLoad")
    static let llmModelDidUnload = Notification.Name("college.llmModelDidUnload")
}
