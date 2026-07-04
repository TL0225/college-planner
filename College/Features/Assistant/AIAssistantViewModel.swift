// AIAssistantViewModel.swift
// Feature: Assistant
// Purpose: Assistant module — AIAssistantViewModel.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine

@MainActor
final class AIAssistantViewModel: ObservableObject {
    @Published var isResponding: Bool = false
    @Published var streamingMessageID: UUID?
    @Published var activeAssistantToolName: String?

    private var activeGenerationTask: Task<Void, Never>?
    private var requestCounter: Int = 0

    func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    func cancelActiveGeneration() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        streamingMessageID = nil
        isResponding = false
        activeAssistantToolName = nil
    }

    func startGeneration(_ operation: @escaping @MainActor () async -> Void) {
        activeGenerationTask?.cancel()
        isResponding = true
        activeGenerationTask = Task { @MainActor in
            defer {
                self.isResponding = false
                self.activeGenerationTask = nil
                self.streamingMessageID = nil
                self.activeAssistantToolName = nil
            }
            await operation()
        }
    }
}
