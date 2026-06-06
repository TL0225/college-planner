import Foundation

public enum GoogleAuthError: Error, Sendable {
    case missingConfiguration
    case invalidConfiguration(String)
    case invalidURL
    case userCancelled
    case unableToStartSession
    case authenticationFailed(Error)
    case invalidResponse
    case tokenSerializationError
}

@MainActor
public protocol GoogleCalendarAuthPort: AnyObject {
    func signIn(completion: @escaping @Sendable (Result<Void, Error>) -> Void)
    func signOut()
    func forceSignOut()
    func validAccessToken() async throws -> String
}

@MainActor
public enum GoogleCalendarAuthAccess {
    public static weak var service: (any GoogleCalendarAuthPort)?
}
