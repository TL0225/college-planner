// TranslationService.swift
// Feature: Core
// Purpose: MainActor translation coordinator wrapping LanguageAvailability and session batching.

import Foundation
import Observation
@preconcurrency import Translation

@MainActor
@Observable
final class TranslationService {
    struct PendingTranslation: Identifiable, Sendable {
        let id: String
        let sourceText: String
    }

    private(set) var supportedLanguages: [Locale.Language] = []
    private(set) var activeRequests: [PendingTranslation] = []

    var sessionConfiguration: TranslationSession.Configuration?

    private let cache = TranslationCache.shared
    private var continuations: [String: CheckedContinuation<String, Never>] = [:]

    var targetLanguageCode: String {
        TranslationPreferences.targetLanguageCode
    }

    var sourceLanguageCode: String {
        TranslationPreferences.sourceLanguageCode
    }

    var targetLanguage: Locale.Language {
        TranslationPreferences.targetLanguage
    }

    var sourceLanguage: Locale.Language {
        TranslationPreferences.sourceLanguage
    }

    var needsTranslation: Bool {
        TranslationPreferences.needsTranslation
    }

    func bootstrapIfNeeded() async {
        guard supportedLanguages.isEmpty else { return }
        supportedLanguages = await TranslationAvailabilityLoader.supportedLanguages()
    }

    func isSupported(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        let status = await TranslationAvailabilityLoader.status(from: source, to: target)
        switch status {
        case .installed, .supported:
            return true
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }

    func cachedTranslation(for sourceText: String) -> String? {
        guard needsTranslation else { return sourceText }
        return cache.lookup(sourceText: sourceText, targetLanguageCode: targetLanguageCode)
    }

    func translate(_ sourceText: String) async -> String {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sourceText }
        guard needsTranslation else { return sourceText }

        if let cached = cache.lookup(sourceText: trimmed, targetLanguageCode: targetLanguageCode) {
            return cached
        }

        guard await isSupported(from: sourceLanguage, to: targetLanguage) else {
            return trimmed
        }

        return await withCheckedContinuation { continuation in
            let id = UUID().uuidString
            continuations[id] = continuation
            activeRequests.append(PendingTranslation(id: id, sourceText: trimmed))
            triggerSession()
        }
    }

    func handleSession(_ session: TranslationSession) async {
        let batch = activeRequests
        guard !batch.isEmpty else { return }

        do {
            for pending in batch {
                let response = try await session.translate(pending.sourceText)
                cache.store(
                    sourceText: response.sourceText,
                    targetLanguageCode: targetLanguageCode,
                    translatedText: response.targetText
                )
                resumeContinuation(id: pending.id, value: response.targetText)
            }
        } catch {
            for pending in batch {
                resumeContinuation(id: pending.id, value: pending.sourceText)
            }
        }

        activeRequests.removeAll()
        sessionConfiguration = nil
    }

    func invalidateCache() {
        cache.removeAll()
    }

    private func triggerSession() {
        if sessionConfiguration == nil {
            sessionConfiguration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: TranslationPolicy.preferredStrategy
            )
        } else {
            sessionConfiguration?.invalidate()
        }
    }

    private func resumeContinuation(id: String, value: String) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        continuation.resume(returning: value)
    }
}
