// CatalogSigningKeyManager.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSigningKeyManager.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation
import Security

/// Per-device Ed25519 signing key for catalog bundle export.
final class CatalogSigningKeyManager: @unchecked Sendable {
    static let shared = CatalogSigningKeyManager()

    private let lock = NSLock()
    private var cachedPrivateKey: Curve25519.Signing.PrivateKey?

    private init() {}

    var privateKey: Curve25519.Signing.PrivateKey {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedPrivateKey { return cached }
        let key = (try? loadPrivateKey()) ?? {
            let newKey = Curve25519.Signing.PrivateKey()
            try? savePrivateKey(newKey)
            return newKey
        }()
        cachedPrivateKey = key
        return key
    }

    var publicKey: Curve25519.Signing.PublicKey {
        privateKey.publicKey
    }

    var fingerprint: String {
        Self.fingerprint(for: publicKey)
    }

    static func fingerprint(for publicKey: Curve25519.Signing.PublicKey) -> String {
        let digest = SHA256.hash(data: publicKey.rawRepresentation)
        return digest.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Keychain

    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "College") + ".catalog.signing"
    }

    private static let account = "catalog.signing.key.v1"

    private func loadPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.copyFailed(status: status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) throws {
        let data = key.rawRepresentation

        func addItem(_ attrs: [String: Any]) throws {
            SecItemDelete(attrs as CFDictionary)
            let status = SecItemAdd(attrs as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status: status) }
        }

        var cfErr: Unmanaged<CFError>?
        if let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [],
            &cfErr
        ) {
            let protected: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.service,
                kSecAttrAccount as String: Self.account,
                kSecAttrAccessControl as String: access,
                kSecValueData as String: data,
            ]
            do {
                try addItem(protected)
                return
            } catch let KeychainError.saveFailed(status: status) where status == -34018 {
                // Fall through for ad-hoc signing.
            } catch {
                // Fall through.
            }
        }

        let fallback: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        try addItem(fallback)
    }

    enum KeychainError: Error {
        case copyFailed(status: OSStatus)
        case saveFailed(status: OSStatus)
    }
}
