import Foundation

actor VaultImportSerialQueue {
    static let shared = VaultImportSerialQueue()

    func run<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
