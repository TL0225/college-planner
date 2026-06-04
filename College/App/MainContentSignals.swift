// MainContentSignals.swift
// Feature: App
// Purpose: App module — MainContentReadyPreferenceKey.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Cross-view signals used to coordinate the post-unlock transition.
struct MainContentReadyPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct MainContentReadySignal: View {
    let ready: Bool

    var body: some View {
        Color.clear
            .preference(key: MainContentReadyPreferenceKey.self, value: ready)
            .allowsHitTesting(false)
    }
}
