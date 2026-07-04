// LocalizedText.swift
// Feature: Core
// Purpose: Resolves English catalog strings and translates when target language differs.

import SwiftUI

struct LocalizedText: View {
    private enum Source {
        case key(String, table: String?)
        case resolved(String)
    }

    private let source: Source

    @Environment(TranslationService.self) private var translationService
    @State private var displayText = ""

    init(_ key: String, table: String? = nil) {
        self.source = .key(key, table: table)
    }

    /// Use when the English string is already resolved (e.g. chrome titles that
    /// come from `String(localized:)`), so it still flows through machine translation.
    init(english: String) {
        self.source = .resolved(english)
    }

    var body: some View {
        Text(displayText)
            .task(id: refreshToken) {
                await refreshDisplayText()
            }
    }

    private var refreshToken: String {
        "\(englishText)|\(translationService.targetLanguageCode)"
    }

    private var englishText: String {
        switch source {
        case let .key(key, table):
            if let table {
                return String(
                    localized: String.LocalizationValue(key),
                    table: table,
                    bundle: .main
                )
            }
            return String(localized: String.LocalizationValue(key))
        case let .resolved(text):
            return text
        }
    }

    @MainActor
    private func refreshDisplayText() async {
        let english = englishText
        if translationService.needsTranslation {
            displayText = await translationService.translate(english)
        } else {
            displayText = english
        }
    }
}
