import Foundation
import SwiftUI
import CryptoKit
import LocalAuthentication
import Security
import CoreData
import Combine
import os
#if canImport(AppKit)
import AppKit
#endif

/// Central security coordinator:
/// - Holds an in-memory master key (after user presence)
/// - Encrypts/decrypts sensitive blobs stored in Core Data/UserDefaults/files
/// - Provides a simple "locked/unlocked" state for the UI
@MainActor
final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()

    private let logger = Logger(subsystem: "Timothy.College", category: "Security")

    /// When enabled, sensitive on-disk fields are stored encrypted and the UI requires an unlock step.
    @AppStorage("security.encryptionEnabled") private var encryptionEnabledStorage: Bool = true

    /// Best-effort migration can be expensive (Core Data fetch + file IO). Only run once.
    @AppStorage("security.didMigrateSensitiveBlobs.v1") private var didMigrateSensitiveBlobsV1: Bool = false

    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var lastUnlockError: String? = nil

    private(set) var masterKey: SymmetricKey? = nil

    private var ongoingUnlockTask: Task<Bool, Never>? = nil

    var encryptionEnabled: Bool { false } // Forced to false per user request

    private init() {}

    func setLastUnlockErrorForDisplay(_ message: String?) {
        lastUnlockError = message
        #if DEBUG
        if let message, !message.isEmpty {
            UnlockDebugLog.log("SecurityManager.lastUnlockError <- \(message)")
        } else {
            UnlockDebugLog.log("SecurityManager.lastUnlockError cleared")
        }
        #endif
    }

    /// Completes the unlock process *after* authentication has already succeeded.
    ///
    /// Use this with SwiftUI `LocalAuthenticationView` (LocalAuthentication framework),
    /// which is the Apple-documented way to present the authentication UI in SwiftUI.
    func completeUnlockAfterAuthentication() async -> Bool {
        if let existing = ongoingUnlockTask {
            #if DEBUG
            UnlockDebugLog.log("SecurityManager.completeUnlockAfterAuthentication(): join ongoing unlock task")
            #endif
            return await existing.value
        }

        let unlockStart = Date()

        let task = Task<Bool, Never> {
            self.lastUnlockError = nil

            #if DEBUG
            UnlockDebugLog.log("SecurityManager.completeUnlockAfterAuthentication(): start (encryptionEnabled=\(self.encryptionEnabled ? "true" : "false"))")
            #endif

            guard self.encryptionEnabled else {
                self.isUnlocked = true
                self.logger.info("Unlock skipped (encryption disabled)")
                #if DEBUG
                UnlockDebugLog.log("SecurityManager.completeUnlockAfterAuthentication(): encryption disabled -> isUnlocked=true")
                #endif
                return true
            }

            do {
                try await self.performPostAuthenticationUnlock(unlockStart: unlockStart, source: "completeUnlockAfterAuthentication")
                return true
            } catch {
                self.lastUnlockError = error.localizedDescription
                self.isUnlocked = false
                self.logger.error("Post-auth unlock failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                let totalElapsed = Date().timeIntervalSince(unlockStart)
                UnlockDebugLog.log("SecurityManager.completeUnlockAfterAuthentication(): FAILED: \(error.localizedDescription)")
                UnlockDebugLog.log(String(format: "SecurityManager.completeUnlockAfterAuthentication(): failed after %.3fs", totalElapsed))
                #endif
                return false
            }
        }

        ongoingUnlockTask = task
        let result = await task.value
        ongoingUnlockTask = nil
        return result
    }

    private func performPostAuthenticationUnlock(unlockStart: Date, source: String) async throws {
        #if DEBUG
        UnlockDebugLog.log("SecurityManager.performPostAuthenticationUnlock(\(source)): loading master key")
        #endif

        // Keychain can be slow; do it off the main actor to avoid UI stalls.
        let key = try await Task.detached(priority: .userInitiated) {
            #if DEBUG
            let t0 = Date()
            UnlockDebugLog.log("KeychainMasterKey.getOrCreateMasterKey(): begin")
            defer {
                let dt = Date().timeIntervalSince(t0)
                UnlockDebugLog.log(String(format: "KeychainMasterKey.getOrCreateMasterKey(): end (%.3fs)", dt))
            }
            #endif
            return try KeychainMasterKey.getOrCreateMasterKey()
        }.value

        self.masterKey = key
        self.isUnlocked = true
        self.logger.info("Unlock succeeded; isUnlocked=true")
        #if DEBUG
        UnlockDebugLog.log("SecurityManager.performPostAuthenticationUnlock(\(source)): SUCCESS (isUnlocked=true)")
        let totalElapsed = Date().timeIntervalSince(unlockStart)
        UnlockDebugLog.log(String(format: "SecurityManager.performPostAuthenticationUnlock(\(source)): done (%.3fs)", totalElapsed))
        #endif

        // Best-effort: migrate existing sensitive blobs to encrypted form.
        // IMPORTANT: don't do this immediately after unlock; letting SwiftUI render first avoids
        // the "white window" effect caused by main-thread stalls during initial fetch/layout.
        if !self.didMigrateSensitiveBlobsV1 {
            self.didMigrateSensitiveBlobsV1 = true
            let container = CoreDataManager.shared.container
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                SensitiveBlobMigration.migrate(container: container, key: key)
            }
        }
    }

    func setEncryptionEnabled(_ enabled: Bool) {
        encryptionEnabledStorage = enabled
        if !enabled {
            // If a user disables encryption, we also drop the in-memory key.
            // We do NOT automatically decrypt data-at-rest; that should be an explicit user action.
            lock()
        }
    }

    func lock() {
        masterKey = nil
        isUnlocked = false
        lastUnlockError = nil

        logger.info("Locked")
        #if DEBUG
        UnlockDebugLog.log("SecurityManager.lock()")
        #endif
    }

    /// Unlocks the app by requiring user presence (Touch ID or password).
    /// On success, loads/creates the master key in Keychain with user-presence protection.
    func unlock(reason: String = "Unlock to access your encrypted data") async -> Bool {
        if let existing = ongoingUnlockTask {
            #if DEBUG
            UnlockDebugLog.log("SecurityManager.unlock(): join ongoing unlock task")
            #endif
            return await existing.value
        }

        let unlockStart = Date()

        let task = Task<Bool, Never> {
            self.lastUnlockError = nil

            #if DEBUG
            UnlockDebugLog.log("SecurityManager.unlock(): start (encryptionEnabled=\(self.encryptionEnabled ? "true" : "false"))")
            #endif

            guard self.encryptionEnabled else {
                // If encryption is disabled, we don't require unlock.
                self.isUnlocked = true
                self.logger.info("Unlock skipped (encryption disabled)")
                #if DEBUG
                UnlockDebugLog.log("SecurityManager.unlock(): encryption disabled -> isUnlocked=true")
                #endif
                return true
            }

            do {
                self.logger.info("Begin unlock")
                #if DEBUG
                UnlockDebugLog.log("SecurityManager.unlock(): begin")
                UnlockDebugLog.log("SecurityManager.unlock(): presenting auth prompt")
                #endif

                // Always require user presence for the app unlock UX.
                // NOTE: Run on MainActor so the system auth UI is reliably presented.
                let ctx = LAContext()
                ctx.localizedCancelTitle = "Cancel"

                #if canImport(AppKit)
                // If the app is not active/frontmost, macOS can fail to show the auth prompt,
                // leaving the user staring at a blank window while we await evaluatePolicy().
                if !NSApplication.shared.isActive {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                NSApplication.shared.keyWindow?.makeKeyAndOrderFront(nil)
                #if DEBUG
                UnlockDebugLog.log("SecurityManager.unlock(): activated app for auth UI")
                #endif
                #endif

                var evalError: NSError?
                guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
                    throw evalError ?? UnlockError.authenticationUnavailable
                }
                _ = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)

                #if DEBUG
                let authElapsed = Date().timeIntervalSince(unlockStart)
                UnlockDebugLog.log(String(format: "SecurityManager.unlock(): auth OK (%.3fs)", authElapsed))
                #endif

                #if DEBUG
                UnlockDebugLog.log("SecurityManager.unlock(): auth OK; loading master key")
                #endif

                #if DEBUG
                // Watchdog: if we stall after auth, emit timestamps into the same user-visible log.
                let watchdogToken = UUID().uuidString
                Task.detached(priority: .utility) {
                    for seconds in [2, 5, 15] {
                        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                        await MainActor.run {
                            if self.ongoingUnlockTask != nil && !self.isUnlocked {
                                let elapsed = Date().timeIntervalSince(unlockStart)
                                UnlockDebugLog.log(String(format: "SecurityManager.unlock(): WATCHDOG(%@) still pending after %ds (elapsed=%.3fs)", watchdogToken, seconds, elapsed))
                            }
                        }
                    }
                }
                #endif

                try await self.performPostAuthenticationUnlock(unlockStart: unlockStart, source: "unlock")
                return true
            } catch {
                self.lastUnlockError = error.localizedDescription
                self.isUnlocked = false
                self.logger.error("Unlock failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                UnlockDebugLog.log("SecurityManager.unlock(): FAILED: \(error.localizedDescription)")
                let totalElapsed = Date().timeIntervalSince(unlockStart)
                UnlockDebugLog.log(String(format: "SecurityManager.unlock(): failed after %.3fs", totalElapsed))
                #endif
                return false
            }
        }

        ongoingUnlockTask = task
        let result = await task.value
        ongoingUnlockTask = nil
        return result
    }

    // MARK: - Encrypt/decrypt helpers (blob fields)

    func encryptBlobForStorage(_ data: Data?) -> Data? {
        guard let data else { return nil }
        guard encryptionEnabled else { return data }
        guard let key = masterKey else { return data } // locked: avoid bricking; UI should gate writes
        return (try? BlobCrypto.encryptIfNeeded(data, using: key)) ?? data
    }

    func decryptBlobFromStorage(_ data: Data?) -> Data? {
        guard let data else { return nil }
        guard encryptionEnabled else { return data }
        guard let key = masterKey else { return nil }
        return (try? BlobCrypto.decryptIfNeeded(data, using: key)) ?? nil
    }

    // MARK: - Secure UserDefaults (encrypted-at-rest)

    func secureSetString(_ value: String, forKey key: String) {
        let trimmed = value
        if !encryptionEnabled {
            UserDefaults.standard.set(trimmed, forKey: key)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let enc = encryptBlobForStorage(data)
        UserDefaults.standard.set(enc?.base64EncodedString(), forKey: key)
    }

    func secureGetString(forKey key: String) -> String {
        if !encryptionEnabled {
            return UserDefaults.standard.string(forKey: key) ?? ""
        }
        guard let b64 = UserDefaults.standard.string(forKey: key),
              let enc = Data(base64Encoded: b64),
              let dec = decryptBlobFromStorage(enc),
              let s = String(data: dec, encoding: .utf8) else {
            return ""
        }
        return s
    }

    // MARK: - Migration (best-effort)

}

private enum SensitiveBlobMigration {
    static func migrate(container: NSPersistentContainer, key: SymmetricKey) {
        // Use a private-queue context so migration cannot block the main thread.
        let ctx = container.newBackgroundContext()
        ctx.name = "security.migrateSensitiveBlobs"
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        ctx.perform {
            var changed = false

            // Encrypt Profile blobs.
            let profileReq = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
            profileReq.fetchLimit = 1
            if let profile = (try? ctx.fetch(profileReq))?.first {
                if let d = profile.profilePhotoData, !BlobCrypto.isEncryptedBlob(d), let enc = try? BlobCrypto.encryptIfNeeded(d, using: key) {
                    profile.profilePhotoData = enc
                    changed = true
                }
                if let d = profile.transcriptData, !BlobCrypto.isEncryptedBlob(d), let enc = try? BlobCrypto.encryptIfNeeded(d, using: key) {
                    profile.transcriptData = enc
                    changed = true
                }
            }

            // Encrypt syllabus security-scoped bookmark blobs (CourseOverrideEntity.syllabusFileBookmarkData).
            let req = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
            req.predicate = NSPredicate(format: "syllabusFileBookmarkData != nil")
            let overrides = (try? ctx.fetch(req)) ?? []
            for ov in overrides {
                guard let d = ov.syllabusFileBookmarkData, !BlobCrypto.isEncryptedBlob(d) else { continue }
                if let enc = try? BlobCrypto.encryptIfNeeded(d, using: key) {
                    ov.syllabusFileBookmarkData = enc
                    changed = true
                }
            }

            // Encrypt Document Vault files at rest (best-effort, in-place).
            let vaultDir = documentVaultDirectoryURL()
            let vreq = NSFetchRequest<VaultDocumentEntity>(entityName: "VaultDocumentEntity")
            let docs = (try? ctx.fetch(vreq)) ?? []
            for doc in docs {
                guard let rel = doc.localRelativePath, !rel.isEmpty else { continue }
                let storedURL = vaultDir.appendingPathComponent(rel)
                guard let bytes = try? Data(contentsOf: storedURL) else { continue }
                guard !BlobCrypto.isEncryptedBlob(bytes) else { continue }
                if let enc = try? BlobCrypto.encryptIfNeeded(bytes, using: key) {
                    try? enc.write(to: storedURL, options: [.atomic])
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storedURL.path)
                }
            }

            if changed {
                try? ctx.save()
            }
        }
    }

    private static func documentVaultDirectoryURL() -> URL {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            // Fallback: still return something deterministic.
            return FileManager.default.temporaryDirectory.appendingPathComponent("College/DocumentVault", isDirectory: true)
        }
    }
}

private enum UnlockError: LocalizedError {
    case authenticationUnavailable

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            return "This Mac can't authenticate with Touch ID or password."
        }
    }
}

// MARK: - Blob crypto format

enum BlobCrypto {
    private static let magic = Data("COLENC1".utf8)

    static func isEncryptedBlob(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    static func encryptIfNeeded(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        if isEncryptedBlob(plaintext) { return plaintext }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.missingCombined }
        return magic + combined
    }

    static func decryptIfNeeded(_ stored: Data, using key: SymmetricKey) throws -> Data {
        guard isEncryptedBlob(stored) else { return stored }
        let combined = stored.dropFirst(magic.count)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    enum CryptoError: Error {
        case missingCombined
    }
}

// MARK: - Keychain master key

enum KeychainMasterKey {
    nonisolated private static var service: String {
        (Bundle.main.bundleIdentifier ?? "College") + ".security.masterkey"
    }
    nonisolated private static let account = "masterkey.v1"

    nonisolated static func getOrCreateMasterKey() throws -> SymmetricKey {
        if let key = try? loadMasterKey() {
            return key
        }
        let newKeyData = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        try saveMasterKey(data: newKeyData)
        // Return the generated key immediately; subsequent unlocks will load from Keychain.
        return SymmetricKey(data: newKeyData)
    }

    nonisolated private static func loadMasterKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.copyFailed(status: status)
        }
        return SymmetricKey(data: data)
    }

    nonisolated private static func saveMasterKey(data: Data) throws {
        // Preferred: Keychain item protected by user presence. This can fail under ad-hoc signing
        // or missing dev identities (commonly OSStatus -34018). We fall back to a standard item.
        func addItem(_ attrs: [String: Any]) throws {
            SecItemDelete(attrs as CFDictionary)
            let status = SecItemAdd(attrs as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status: status) }
        }

        var cfErr: Unmanaged<CFError>?
        if let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            &cfErr
        ) {
            let protected: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessControl as String: access,
                kSecValueData as String: data
            ]
            do {
                try addItem(protected)
                return
            } catch let KeychainError.saveFailed(status: status) where status == -34018 {
                // Fall through to unprotected item.
            } catch {
                // Any other error: fall through to unprotected item (still behind app unlock).
            }
        }

        let fallback: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        try addItem(fallback)
    }

    nonisolated static func deleteMasterKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    nonisolated enum KeychainError: Error {
        case accessControlFailed
        case copyFailed(status: OSStatus)
        case saveFailed(status: OSStatus)
    }
}

extension KeychainMasterKey.KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .accessControlFailed:
            return "Keychain access control creation failed."
        case .copyFailed(let status):
            return "Keychain read failed (OSStatus \(status))."
        case .saveFailed(let status):
            return "Keychain save failed (OSStatus \(status))."
        }
    }
}

