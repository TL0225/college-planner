// TranslationPreferences.swift
// Feature: Core
// Purpose: UserDefaults-backed source/target language preferences for Phase 12 translation.

import Foundation

enum TranslationPreferences {
    static let targetLanguageStorageKey = "translation.targetLanguage"
    static let sourceLanguageStorageKey = "translation.sourceLanguage"
    static let defaultLanguageCode = "en"

    static var targetLanguageCode: String {
        normalizedLanguageCode(
            UserDefaults.standard.string(forKey: targetLanguageStorageKey) ?? defaultLanguageCode
        )
    }

    static var sourceLanguageCode: String {
        normalizedLanguageCode(
            UserDefaults.standard.string(forKey: sourceLanguageStorageKey) ?? defaultLanguageCode
        )
    }

    static var targetLanguage: Locale.Language {
        language(from: targetLanguageCode)
    }

    static var sourceLanguage: Locale.Language {
        language(from: sourceLanguageCode)
    }

    static var needsTranslation: Bool {
        targetLanguageCode != sourceLanguageCode
    }

    static func language(from code: String) -> Locale.Language {
        Locale.Language(identifier: normalizedLanguageCode(code))
    }

    static func displayName(for languageCode: String) -> String {
        let code = normalizedLanguageCode(languageCode)
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    static func displayName(for language: Locale.Language) -> String {
        displayName(for: languageCode(for: language))
    }

    static func languageCode(for language: Locale.Language) -> String {
        if let code = language.languageCode?.identifier {
            return code
        }
        return language.minimalIdentifier
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultLanguageCode : trimmed
    }
}
