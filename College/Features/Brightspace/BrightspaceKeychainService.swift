// BrightspaceKeychainService.swift
// Feature: Brightspace
// Purpose: Brightspace module — BrightspaceKeychainService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Security

// MARK: - BrightspaceKeychainService
// Stores Brightspace credentials (username + password) in the system Keychain
// using kSecClassInternetPassword keyed by portal host.

final class BrightspaceKeychainService: @unchecked Sendable {

    static let shared = BrightspaceKeychainService()
    private init() {}

    private var keychainService: String {
        (Bundle.main.bundleIdentifier ?? "com.college") + ".brightspace"
    }

    // MARK: - Save

    @discardableResult
    func save(username: String, password: String, host: String) -> Bool {
        guard
            let usernameData = username.data(using: .utf8),
            let passwordData = password.data(using: .utf8)
        else { return false }

        // Store username under "<host>.username"
        saveRaw(data: usernameData, account: "\(host).username")
        // Store password under "<host>.password"
        return saveRaw(data: passwordData, account: "\(host).password")
    }

    // MARK: - Load

    func load(host: String) -> (username: String, password: String)? {
        guard
            let usernameData = loadRaw(account: "\(host).username"),
            let passwordData = loadRaw(account: "\(host).password"),
            let username = String(data: usernameData, encoding: .utf8),
            let password = String(data: passwordData, encoding: .utf8)
        else { return nil }
        return (username, password)
    }

    // MARK: - Delete

    @discardableResult
    func delete(host: String) -> Bool {
        deleteRaw(account: "\(host).username")
        return deleteRaw(account: "\(host).password")
    }

    // MARK: - Private Helpers

    @discardableResult
    private func saveRaw(data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadRaw(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private func deleteRaw(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
