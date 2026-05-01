import Foundation
import AuthenticationServices
import Security
import CryptoKit
import Combine
import LocalAuthentication

enum GoogleAuthError: Error {
    case missingConfiguration
    case invalidConfiguration(String)
    case invalidURL
    case userCancelled
    case unableToStartSession
    case authenticationFailed(Error)
    case invalidResponse
    case tokenSerializationError
}

class GoogleAuthService: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = GoogleAuthService()

    private enum KeychainReadMode {
        /// Allow Keychain UI if required (normal behavior for user-driven actions).
        case interactive
        /// Never trigger Keychain UI; return nil when interaction would be required.
        case nonInteractive
    }
    
    @Published var isAuthenticated: Bool = false

    // Must be strongly retained for the auth UI to appear.
    private var currentAuthSession: ASWebAuthenticationSession?

    // Privacy/security: avoid shared session cookies/caches for OAuth token calls.
    private lazy var secureSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    #if DEBUG
    private enum DebugFileLogger {
        private static let queue = DispatchQueue(label: "College.GoogleOAuth.DebugFileLogger")
        private static let isoFormatterLock = NSLock()
        nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

        private static var fileURL: URL? {
            GoogleDebugLog.fileURL()
        }

        private static func isoTimestamp(_ date: Date) -> String {
            isoFormatterLock.lock()
            defer { isoFormatterLock.unlock() }
            return isoFormatter.string(from: date)
        }

        static func log(_ message: String) {
            queue.async {
                guard let url = fileURL else { return }

                GoogleDebugLog.ensureFileExists()

                let timestamp = isoTimestamp(Date())
                let line = "[\(timestamp)] \(message)\n"

                do {
                    let data = line.data(using: .utf8) ?? Data()
                    if FileManager.default.fileExists(atPath: url.path) {
                        let handle = try FileHandle(forWritingTo: url)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } else {
                        try data.write(to: url, options: .atomic)
                    }
                } catch {
                    // Intentionally ignore logging failures in DEBUG helper.
                }
            }
        }
    }

    private func debugLog(_ message: String) {
        DebugFileLogger.log(message)
    }
    #endif
    
    // MARK: - Configuration
    private enum ConfigKeys {
        static let plistClientID = "GOOGLE_CLIENT_ID"
        static let plistRedirectURI = "GOOGLE_REDIRECT_URI"
    }

    private struct EffectiveConfig {
        let clientID: String
        let redirectURI: String
        let callbackScheme: String
    }

    private func effectiveConfig() throws -> EffectiveConfig {
        let savedClientID = Bundle.main.object(forInfoDictionaryKey: ConfigKeys.plistClientID) as? String
        let savedRedirectURI = Bundle.main.object(forInfoDictionaryKey: ConfigKeys.plistRedirectURI) as? String
        
        guard let clientID = savedClientID?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty,
              let redirectURI = savedRedirectURI?.trimmingCharacters(in: .whitespacesAndNewlines), !redirectURI.isEmpty else {
            throw GoogleAuthError.missingConfiguration
        }

        // Determine scheme from redirect URI if possible, otherwise construct it
        // Scheme is usually the part before ":/oauth2redirect"
        // E.g. com.googleusercontent.apps.123:/oauth2redirect -> scheme: com.googleusercontent.apps.123
        let callbackScheme: String
        if let url = URL(string: redirectURI), let scheme = url.scheme {
            callbackScheme = scheme
        } else {
             // Fallback: reverse the client ID (standard Google pattern)
             // CLIENT_ID: 123.apps.googleusercontent.com
             // SCHEME: com.googleusercontent.apps.123
             let components = clientID.components(separatedBy: ".")
             if components.count > 1 {
                 callbackScheme = components.reversed().joined(separator: ".")
             } else {
                 callbackScheme = "com.googleusercontent.apps.\(clientID)"
             }
        }

        return EffectiveConfig(
            clientID: clientID,
            redirectURI: redirectURI,
            callbackScheme: callbackScheme
        )
    }

    private func formURLEncodedBody(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    var clientID: String {
        (try? effectiveConfig().clientID) ?? ""
    }
    
    var redirectURI: String {
        (try? effectiveConfig().redirectURI) ?? ""
    }
    
    // MARK: - Auth State
    private let kAccessTokenKey = "google_access_token"
    private let kRefreshTokenKey = "google_refresh_token"
    private let kTokenExpiryKey = "google_token_expiry"

    // Namespace keychain items by service to avoid collisions and reduce access prompts.
    private let keychainService: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        return "\(bundleID).google.oauth"
    }()

    // Cache values in memory so we don't hit Keychain on every background sync tick.
    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedExpiryTime: TimeInterval?
    
    override init() {
        super.init()
    }

    /// Returns true when the refresh token can be read from Keychain without UI.
    /// Used by launch-time flows to avoid repeated prompt loops at startup.
    func hasUsableSessionForBackgroundStart() -> Bool {
        restorePreviousSessionIfPossibleForBackgroundStart()
    }
    
    private func restorePreviousSessionIfPossibleForBackgroundStart() -> Bool {
        // Require both access token and refresh token to consider the session valid.
        guard let _ = getFromKeychain(key: kAccessTokenKey, mode: .nonInteractive),
              let _ = getFromKeychain(key: kRefreshTokenKey, mode: .nonInteractive) else {
            self.isAuthenticated = false
            return false
        }
        self.isAuthenticated = true
        return true
    }
    
    // MARK: - Authentication Flow
    
    /// Starts the OAuth2 authentication flow using ASWebAuthenticationSession
    @MainActor
    func signIn(completion: @Sendable @escaping (Result<Void, Error>) -> Void) {
        let config: EffectiveConfig
        do {
            config = try effectiveConfig()
        } catch {
            completion(.failure(error))
            return
        }

        #if DEBUG
        debugLog("Google OAuth signIn() starting")
        debugLog("Effective config: client_id=\(config.clientID) redirect_uri=\(config.redirectURI) callback_scheme=\(config.callbackScheme)")
        #endif
        
        // 1. Generate State and PKCE Verifier
        let state = UUID().uuidString
        let codeVerifier = generateCodeVerifier()
        guard let codeChallenge = generateCodeChallenge(from: codeVerifier) else {
            completion(.failure(GoogleAuthError.invalidURL))
            return
        }
        
        // 2. Construct Authorization URL
        // https://accounts.google.com/o/oauth2/v2/auth
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            completion(.failure(GoogleAuthError.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            // Need a write-capable scope for creating/deleting events.
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"), // Request refresh token
            URLQueryItem(name: "prompt", value: "consent")       // Force consent to ensure refresh token
        ]
        
        guard let authURL = components.url else {
            completion(.failure(GoogleAuthError.invalidURL))
            return
        }

        #if DEBUG
        debugLog("Authorize URL: \(authURL.absoluteString)")
        #endif

        // 3. Start Session
        let scheme = config.callbackScheme

        // Explicitly type the callback as a plain @Sendable closure (no @MainActor).
        // Because signIn() is @MainActor, any closure defined inline is inferred as
        // @MainActor too. ASWebAuthenticationSession delivers its callback on a
        // background XPC thread, so the Swift runtime's isolation thunk would fire
        // _swift_task_checkIsolatedSwift *before* the closure body even runs,
        // crashing with EXC_BREAKPOINT (dispatch_assert_queue_fail). By providing
        // an explicit non-actor-isolated @Sendable type we prevent that inference,
        // then hop to MainActor manually via Task { @MainActor in }.
        let oauthCallback: @Sendable (URL?, Error?) -> Void = { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.currentAuthSession = nil }

                if let error = error {
                    #if DEBUG
                    self.debugLog("ASWebAuthenticationSession finished with error: \(error.localizedDescription)")
                    #endif
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        completion(.failure(GoogleAuthError.userCancelled))
                    } else {
                        completion(.failure(GoogleAuthError.authenticationFailed(error)))
                    }
                    return
                }

                guard let callbackURL = callbackURL,
                      let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value,
                      let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
                      returnedState == state else {
                    #if DEBUG
                    let urlString = callbackURL?.absoluteString ?? "<nil>"
                    self.debugLog("OAuth callback missing code/state or state mismatch. callbackURL=\(urlString)")
                    #endif
                    completion(.failure(GoogleAuthError.invalidResponse))
                    return
                }

                #if DEBUG
                self.debugLog("OAuth callback received authorization code (len=\(code.count)). Exchanging for token...")
                #endif

                // 4. Exchange Code for Token
                self.exchangeCodeForToken(
                    code: code,
                    codeVerifier: codeVerifier,
                    clientID: config.clientID,
                    redirectURI: config.redirectURI,
                    completion: completion
                )
            }
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme, completionHandler: oauthCallback)
        session.presentationContextProvider = self

        // Retain session (required) and start on MainActor.
        self.currentAuthSession = session
        let started = session.start()
        #if DEBUG
        self.debugLog("ASWebAuthenticationSession start() -> \(started)")
        #endif
        if !started {
            self.currentAuthSession = nil
            completion(.failure(GoogleAuthError.unableToStartSession))
        }
    }
    
    @MainActor
    func signOut() {
        // Fire-and-forget revocation so Google can invalidate the refresh token immediately.
        // Use non-interactive lookup so sign-out paths never trigger Keychain UI during launch.
        if let refreshToken = cachedRefreshToken ?? getFromKeychain(key: kRefreshTokenKey, mode: .nonInteractive) {
            revokeRefreshTokenAsync(refreshToken)
        }
        forceSignOut()
    }

    /// Clears local state without revoking at Google. Used when the token is already invalid.
    @MainActor
    func forceSignOut() {
        removeFromKeychain(key: kAccessTokenKey)
        removeFromKeychain(key: kRefreshTokenKey)
        removeFromKeychain(key: kTokenExpiryKey)

        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedExpiryTime = nil

        self.isAuthenticated = false
    }

    nonisolated private func revokeRefreshTokenAsync(_ token: String) {
        guard let url = URL(string: "https://oauth2.googleapis.com/revoke") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(token)".data(using: .utf8)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForToken(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String,
        completion: @Sendable @escaping (Result<Void, Error>) -> Void
    ) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(.failure(GoogleAuthError.invalidURL))
            return
        }

        #if DEBUG
        debugLog("Token exchange starting: client_id=\(clientID) redirect_uri=\(redirectURI) code_len=\(code.count)")
        #endif
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code": code,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]

        request.httpBody = formURLEncodedBody(parameters)
        
        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                Task { @MainActor in
                    GoogleAuthService.shared.debugLog("Token exchange network error: \(error.localizedDescription)")
                }
                #endif
                Task { @MainActor in completion(.failure(error)) }
                return
            }

            #if DEBUG
            if let http = response as? HTTPURLResponse {
                Task { @MainActor in
                    GoogleAuthService.shared.debugLog("Token exchange HTTP status: \(http.statusCode)")
                }
            }
            #endif

            guard let data else {
                Task { @MainActor in completion(.failure(GoogleAuthError.invalidResponse)) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    let refreshToken = json["refresh_token"] as? String
                    let expiresIn = json["expires_in"] as? TimeInterval

                    Task { @MainActor in
                        #if DEBUG
                        GoogleAuthService.shared.debugLog("Token exchange success (access_token received).")
                        #endif

                        GoogleAuthService.shared.saveToKeychain(key: GoogleAuthService.shared.kAccessTokenKey, value: accessToken)
                        GoogleAuthService.shared.cachedAccessToken = accessToken

                        if let refreshToken {
                            GoogleAuthService.shared.saveToKeychain(key: GoogleAuthService.shared.kRefreshTokenKey, value: refreshToken)
                            GoogleAuthService.shared.cachedRefreshToken = refreshToken
                        }

                        if let expiresIn {
                            let expiryDate = Date().addingTimeInterval(expiresIn)
                            GoogleAuthService.shared.saveToKeychain(key: GoogleAuthService.shared.kTokenExpiryKey, value: String(expiryDate.timeIntervalSince1970))
                            GoogleAuthService.shared.cachedExpiryTime = expiryDate.timeIntervalSince1970
                        }

                        GoogleAuthService.shared.isAuthenticated = true
                        completion(.success(()))
                    }
                } else {
                    #if DEBUG
                    Task { @MainActor in
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let err = json["error"] as? String ?? "<missing error>"
                            let desc = json["error_description"] as? String ?? "<missing error_description>"
                            GoogleAuthService.shared.debugLog("Token exchange failed: error=\(err) description=\(desc)")
                        } else {
                            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                            GoogleAuthService.shared.debugLog("Token exchange failed: unparseable response body (truncated)=\(raw.prefix(500))")
                        }
                    }
                    #endif
                    Task { @MainActor in completion(.failure(GoogleAuthError.tokenSerializationError)) }
                }
            } catch {
                #if DEBUG
                Task { @MainActor in
                    GoogleAuthService.shared.debugLog("Token exchange JSON parse error: \(error.localizedDescription)")
                }
                #endif
                Task { @MainActor in completion(.failure(error)) }
            }
        }.resume()
    }
    
    // MARK: - Token Access
    
    func getValidAccessToken(completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        // Check if token is expired
        let expiryTime: TimeInterval? = {
            if let cachedExpiryTime { return cachedExpiryTime }
            if let expiryStr = getFromKeychain(key: kTokenExpiryKey, mode: .nonInteractive), let t = TimeInterval(expiryStr) {
                cachedExpiryTime = t
                return t
            }
            return nil
        }()

        if let expiryTime, Date().addingTimeInterval(60).timeIntervalSince1970 < expiryTime {
            // Token is still valid
            if let token = cachedAccessToken ?? getFromKeychain(key: kAccessTokenKey, mode: .nonInteractive) {
                cachedAccessToken = token
                completion(.success(token))
                return
            }
        }
        
        // Token expired or missing, try refresh
        refreshAccessToken(completion: completion)
    }
    
    private func refreshAccessToken(completion: @Sendable @escaping (Result<String, Error>) -> Void) {
        guard let refreshToken = cachedRefreshToken ?? getFromKeychain(key: kRefreshTokenKey, mode: .nonInteractive) else {
            completion(.failure(GoogleAuthError.missingConfiguration)) // Re-login required
            return
        }

        cachedRefreshToken = refreshToken

        let config: EffectiveConfig
        do {
            config = try effectiveConfig()
        } catch {
            completion(.failure(error))
            return
        }
        
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(.failure(GoogleAuthError.invalidURL))
            return
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": config.clientID,
            "refresh_token": refreshToken, // Only needed for refresh
            "grant_type": "refresh_token"
        ]

        request.httpBody = formURLEncodedBody(parameters)
        
        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                Task { @MainActor in completion(.failure(error)) }
                return
            }

            guard let data else {
                Task { @MainActor in completion(.failure(GoogleAuthError.invalidResponse)) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    let expiresIn = json["expires_in"] as? TimeInterval

                    Task { @MainActor in
                        GoogleAuthService.shared.saveToKeychain(key: GoogleAuthService.shared.kAccessTokenKey, value: accessToken)
                        GoogleAuthService.shared.cachedAccessToken = accessToken

                        if let expiresIn {
                            let expiryDate = Date().addingTimeInterval(expiresIn)
                            GoogleAuthService.shared.saveToKeychain(key: GoogleAuthService.shared.kTokenExpiryKey, value: String(expiryDate.timeIntervalSince1970))
                            GoogleAuthService.shared.cachedExpiryTime = expiryDate.timeIntervalSince1970
                        }

                        completion(.success(accessToken))
                    }
                } else {
                    // Check for invalid_grant (refresh token revoked or expired).
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorCode = json["error"] as? String,
                       errorCode == "invalid_grant" {
                        Task { @MainActor in
                            GoogleAuthService.shared.forceSignOut()
                            completion(.failure(GoogleAuthError.missingConfiguration))
                        }
                    } else {
                        Task { @MainActor in completion(.failure(GoogleAuthError.tokenSerializationError)) }
                    }
                }
            } catch {
                Task { @MainActor in completion(.failure(error)) }
            }
        }.resume()
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .utf8) else { return nil }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Keychain Helpers

    private func nonInteractiveKeychainContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
    
    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let lookupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            // Never show Keychain UI from background/startup token writes.
            kSecUseAuthenticationContext as String: nonInteractiveKeychainContext()
        ]
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = lookupQuery
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
    
    private func getFromKeychain(key: String, mode: KeychainReadMode = .nonInteractive) -> String? {
        if key == kAccessTokenKey, let cachedAccessToken { return cachedAccessToken }
        if key == kRefreshTokenKey, let cachedRefreshToken { return cachedRefreshToken }
        if key == kTokenExpiryKey, let cachedExpiryTime { return String(cachedExpiryTime) }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if mode == .nonInteractive {
            query[kSecUseAuthenticationContext as String] = nonInteractiveKeychainContext()
        }
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            let value = String(data: data, encoding: .utf8)
            if key == kAccessTokenKey { cachedAccessToken = value }
            if key == kRefreshTokenKey { cachedRefreshToken = value }
            if key == kTokenExpiryKey, let value, let t = TimeInterval(value) { cachedExpiryTime = t }
            return value
        }
        return nil
    }
    
    private func removeFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            // Never prompt for UI while clearing startup auth state.
            kSecUseAuthenticationContext as String: nonInteractiveKeychainContext()
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Swift Concurrency bridge

extension GoogleAuthService {
    /// Async/await wrapper around `getValidAccessToken(completion:)`.
    func validAccessToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            getValidAccessToken { result in
                continuation.resume(with: result)
            }
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}
