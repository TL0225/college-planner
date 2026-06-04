// MacStandaloneSettingsRoot.swift
// Feature: Settings
// Purpose: Settings module — MacStandaloneSettingsRoot.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Hosts the SwiftUI `Settings` scene with unified window chrome from `SettingsSessionController`.
/// Do not use for the in-window `SettingsView` inside `ContentView` — that would replace the main window toolbar.
struct MacStandaloneSettingsRoot: View {
    @StateObject private var session = SettingsSessionController()

    var body: some View {
        SettingsView(activePage: .constant(.settings), session: session)
            .environmentObject(session)
            .frame(minWidth: SettingsMetrics.minWindowWidth, minHeight: SettingsMetrics.minWindowHeight)
            .background(SettingsWindowChromeAttacher(session: session))
    }
}

