import Foundation
import Combine

@MainActor
final class AIAssistantViewModel: ObservableObject {
    @Published var isResponding: Bool = false
    @Published var streamingMessageID: UUID?

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
    }

    func startGeneration(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        activeGenerationTask?.cancel()
        isResponding = true
        activeGenerationTask = Task { @MainActor in
            defer {
                self.isResponding = false
                self.activeGenerationTask = nil
                self.streamingMessageID = nil
            }
            await operation()
        }
    }
}
