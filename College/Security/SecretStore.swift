import Foundation
import Security

/// Stores non-PII secrets (e.g., API keys) in the user's Keychain.
///
/// Notes:
/// - Items are stored as `kSecClassGenericPassword`
/// - Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// - No `userPresence` requirement (the app already gates PII behind unlock)
enum SecretStore {
    enum Key: String {
        // Placeholder keeps the raw-valued enum valid until concrete keys are added.
        case placeholder = "placeholder"
    }

    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "College") + ".secrets"
    }

    static func getString(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setString(_ value: String, for key: Key) throws {
        let data = value.data(using: .utf8) ?? Data()

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        // Replace if present.
        SecItemDelete(attrs as CFDictionary)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status: status) }
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(status: OSStatus)
    }
}

