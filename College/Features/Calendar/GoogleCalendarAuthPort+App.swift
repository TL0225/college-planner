import CollegeCalendar
import Foundation

@MainActor
final class GoogleCalendarAuthPortAdapter: GoogleCalendarAuthPort {
    func signIn(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        GoogleAuthService.shared.signIn { result in
            Task { @MainActor in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func signOut() {
        GoogleAuthService.shared.signOut()
    }

    func forceSignOut() {
        GoogleAuthService.shared.forceSignOut()
    }

    func validAccessToken() async throws -> String {
        try await GoogleAuthService.shared.validAccessToken()
    }
}
