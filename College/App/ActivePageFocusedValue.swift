// ActivePageFocusedValue.swift
// Feature: App
// Purpose: App module — ActivePageFocusedValueKey.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Scene-focused active page for gating page-specific keyboard shortcuts (e.g. Cmd+N).
private struct ActivePageFocusedValueKey: FocusedValueKey {
    typealias Value = AppPage
}

extension FocusedValues {
    var activePage: AppPage? {
        get { self[ActivePageFocusedValueKey.self] }
        set { self[ActivePageFocusedValueKey.self] = newValue }
    }
}
