// TranslationAvailabilityLoader.swift
// Nonisolated loader for LanguageAvailability queries (Swift 6 Sendable boundary).

@preconcurrency import Translation

@MainActor
enum TranslationAvailabilityLoader {
    static func supportedLanguages() async -> [Locale.Language] {
        let checker = LanguageAvailability(preferredStrategy: TranslationPolicy.preferredStrategy)
        return await checker.supportedLanguages
    }

    static func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        let checker = LanguageAvailability(preferredStrategy: TranslationPolicy.preferredStrategy)
        return await checker.status(from: source, to: target)
    }
}
