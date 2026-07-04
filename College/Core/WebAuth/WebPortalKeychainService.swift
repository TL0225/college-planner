// WebPortalKeychainService.swift
// Feature: Core / WebAuth
// Purpose: Shared portal credential storage for LMS and Career apply hosts.

import Foundation
import Security

final class WebPortalKeychainService: @unchecked Sendable {
    static let shared = WebPortalKeychainService()
    private init() {}

    private var bundlePrefix: String {
        Bundle.main.bundleIdentifier ?? "com.college"
    }

    private var keychainService: String {
        bundlePrefix + ".webportal"
    }

    @discardableResult
    func save(username: String, password: String, host: String) -> Bool {
        guard
            let usernameData = username.data(using: .utf8),
            let passwordData = password.data(using: .utf8)
        else { return false }
        saveRaw(data: usernameData, account: "\(host).username")
        return saveRaw(data: passwordData, account: "\(host).password")
    }

    func load(host: String) -> (username: String, password: String)? {
        guard
            let usernameData = loadRaw(account: "\(host).username"),
            let passwordData = loadRaw(account: "\(host).password"),
            let username = String(data: usernameData, encoding: .utf8),
            let password = String(data: passwordData, encoding: .utf8)
        else { return nil }
        return (username, password)
    }

    @discardableResult
    func delete(host: String) -> Bool {
        deleteRaw(account: "\(host).username")
        return deleteRaw(account: "\(host).password")
    }

    /// Migrate a host from LMS keychain namespace if present.
    func migrateFromLMSIfNeeded(host: String) {
        if load(host: host) != nil { return }
        if let legacy = LMSKeychainService.shared.load(host: host) {
            save(username: legacy.username, password: legacy.password, host: host)
        }
    }

    @discardableResult
    private func saveRaw(data: Data, account: String) -> Bool {
        deleteRaw(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadRaw(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    @discardableResult
    private func deleteRaw(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
