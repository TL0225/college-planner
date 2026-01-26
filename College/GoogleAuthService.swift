import Foundation
import AuthenticationServices
import Security
import CryptoKit
import Combine

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

class GoogleAuthService: NSObject, ObservableObject {
    static let shared = GoogleAuthService()
    
    @Published var isAuthenticated: Bool = false

    // Must be strongly retained for the auth UI to appear.
    private var currentAuthSession: ASWebAuthenticationSession?

    #if DEBUG
    private enum DebugFileLogger {
        private static let queue = DispatchQueue(label: "College.GoogleOAuth.DebugFileLogger")

        private static var fileURL: URL? {
            GoogleDebugLog.fileURL()
        }

        static func log(_ message: String) {
            queue.async {
                guard let url = fileURL else { return }

                GoogleDebugLog.ensureFileExists()

                let timestamp = ISO8601DateFormatter().string(from: Date())
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
        checkRestorePreviousSession()
    }
    
    private func checkRestorePreviousSession() {
        if let _ = getFromKeychain(key: kAccessTokenKey) {
            // We have a token, effectively logged in. 
            // In a real app, we might check expiry and refresh immediately if needed.
            self.isAuthenticated = true
        }
    }
    
    // MARK: - Authentication Flow
    
    /// Starts the OAuth2 authentication flow using ASWebAuthenticationSession
    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
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
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
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
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callbackURL, error in
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

        session.presentationContextProvider = self

        // Retain session (required) and start on main thread.
        self.currentAuthSession = session
        DispatchQueue.main.async {
            let started = session.start()
            #if DEBUG
            self.debugLog("ASWebAuthenticationSession start() -> \(started)")
            #endif
            if !started {
                self.currentAuthSession = nil
                completion(.failure(GoogleAuthError.unableToStartSession))
            }
        }
    }
    
    func signOut() {
        removeFromKeychain(key: kAccessTokenKey)
        removeFromKeychain(key: kRefreshTokenKey)
        removeFromKeychain(key: kTokenExpiryKey)

        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedExpiryTime = nil
        
        DispatchQueue.main.async {
            self.isAuthenticated = false
        }
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForToken(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return }

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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                self.debugLog("Token exchange network error: \(error.localizedDescription)")
                #endif
                completion(.failure(error))
                return
            }

            #if DEBUG
            if let http = response as? HTTPURLResponse {
                self.debugLog("Token exchange HTTP status: \(http.statusCode)")
            }
            #endif
            
            guard let data = data else {
                completion(.failure(GoogleAuthError.invalidResponse))
                return
            }
            
            do {
                     if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                         let accessToken = json["access_token"] as? String {

                          #if DEBUG
                          self.debugLog("Token exchange success (access_token received).")
                          #endif
                    
                    self.saveToKeychain(key: self.kAccessTokenKey, value: accessToken)
                    self.cachedAccessToken = accessToken
                    
                    if let refreshToken = json["refresh_token"] as? String {
                        self.saveToKeychain(key: self.kRefreshTokenKey, value: refreshToken)
                        self.cachedRefreshToken = refreshToken
                    }
                    
                    if let expiresIn = json["expires_in"] as? TimeInterval {
                        let expiryDate = Date().addingTimeInterval(expiresIn)
                        self.saveToKeychain(key: self.kTokenExpiryKey, value: String(expiryDate.timeIntervalSince1970))
                        self.cachedExpiryTime = expiryDate.timeIntervalSince1970
                    }
                    
                    DispatchQueue.main.async {
                        self.isAuthenticated = true
                        completion(.success(()))
                    }
                } else {
                    #if DEBUG
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let err = json["error"] as? String ?? "<missing error>"
                        let desc = json["error_description"] as? String ?? "<missing error_description>"
                        self.debugLog("Token exchange failed: error=\(err) description=\(desc)")
                    } else {
                        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                        self.debugLog("Token exchange failed: unparseable response body (truncated)=\(raw.prefix(500))")
                    }
                    #endif
                    completion(.failure(GoogleAuthError.tokenSerializationError))
                }
            } catch {
                #if DEBUG
                self.debugLog("Token exchange JSON parse error: \(error.localizedDescription)")
                #endif
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Token Access
    
    func getValidAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        // Check if token is expired
        let expiryTime: TimeInterval? = {
            if let cachedExpiryTime { return cachedExpiryTime }
            if let expiryStr = getFromKeychain(key: kTokenExpiryKey), let t = TimeInterval(expiryStr) {
                cachedExpiryTime = t
                return t
            }
            return nil
        }()

        if let expiryTime, Date().timeIntervalSince1970 < expiryTime {
            // Token is still valid
            if let token = cachedAccessToken ?? getFromKeychain(key: kAccessTokenKey) {
                cachedAccessToken = token
                completion(.success(token))
                return
            }
        }
        
        // Token expired or missing, try refresh
        refreshAccessToken(completion: completion)
    }
    
    private func refreshAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let refreshToken = cachedRefreshToken ?? getFromKeychain(key: kRefreshTokenKey) else {
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
        
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "client_id": config.clientID,
            "refresh_token": refreshToken, // Only needed for refresh
            "grant_type": "refresh_token"
        ]

        request.httpBody = formURLEncodedBody(parameters)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(GoogleAuthError.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    
                    self.saveToKeychain(key: self.kAccessTokenKey, value: accessToken)
                    self.cachedAccessToken = accessToken
                    
                    if let expiresIn = json["expires_in"] as? TimeInterval {
                        let expiryDate = Date().addingTimeInterval(expiresIn)
                        self.saveToKeychain(key: self.kTokenExpiryKey, value: String(expiryDate.timeIntervalSince1970))
                        self.cachedExpiryTime = expiryDate.timeIntervalSince1970
                    }
                    
                    completion(.success(accessToken))
                } else {
                    completion(.failure(GoogleAuthError.tokenSerializationError))
                }
            } catch {
                completion(.failure(error))
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
    
    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getFromKeychain(key: String) -> String? {
        if key == kAccessTokenKey, let cachedAccessToken { return cachedAccessToken }
        if key == kRefreshTokenKey, let cachedRefreshToken { return cachedRefreshToken }
        if key == kTokenExpiryKey, let cachedExpiryTime { return String(cachedExpiryTime) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
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
            kSecAttrAccount as String: key
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
