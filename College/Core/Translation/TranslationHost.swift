// TranslationHost.swift
// Feature: Core
// Purpose: Hosts SwiftUI translationTask for TranslationService session batching.

import SwiftUI
import Translation

struct TranslationHost<Content: View>: View {
    @Environment(TranslationService.self) private var translationService
    @ViewBuilder private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .translationTask(translationService.sessionConfiguration) { session in
                await translationService.handleSession(session)
            }
            .task {
                await translationService.bootstrapIfNeeded()
            }
    }
}
