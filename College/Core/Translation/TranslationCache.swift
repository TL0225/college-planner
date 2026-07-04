// TranslationCache.swift
// Feature: Core
// Purpose: In-memory translation cache keyed by source hash and target language.

import CryptoKit
import Foundation

final class TranslationCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let sourceHash: String
        let targetLanguageCode: String
    }

    private var storage: [Key: String] = [:]
    private let lock = NSLock()
    private let maxEntries = 512

    static let shared = TranslationCache()

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func evictAll() { removeAll() }

    func lookup(sourceText: String, targetLanguageCode: String) -> String? {
        let key = Key(
            sourceHash: Self.hash(sourceText),
            targetLanguageCode: targetLanguageCode
        )
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func store(sourceText: String, targetLanguageCode: String, translatedText: String) {
        let key = Key(
            sourceHash: Self.hash(sourceText),
            targetLanguageCode: targetLanguageCode
        )
        lock.lock()
        if storage.count >= maxEntries, let firstKey = storage.keys.first {
            storage.removeValue(forKey: firstKey)
        }
        storage[key] = translatedText
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    static func hash(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
