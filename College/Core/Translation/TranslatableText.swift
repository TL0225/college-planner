// TranslatableText.swift
// Feature: Core
// Purpose: Dynamic user content with an explicit translate action.

import SwiftUI

struct TranslatableText: View {
    let text: String

    @Environment(TranslationService.self) private var translationService
    @State private var translatedText: String?
    @State private var isTranslating = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(displayText)

            if translationService.needsTranslation {
                Button {
                    Task { await translateNow() }
                } label: {
                    Image(systemName: isTranslating ? "hourglass" : "translate")
                }
                .buttonStyle(.borderless)
                .help("Translate")
                .disabled(isTranslating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var displayText: String {
        translatedText ?? text
    }

    @MainActor
    private func translateNow() async {
        guard !isTranslating else { return }
        isTranslating = true
        defer { isTranslating = false }
        translatedText = await translationService.translate(text)
    }
}
