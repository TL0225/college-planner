// CareerTrailingInspectorLayout.swift
// Feature: Career
// Purpose: Career module — CareerTrailingInspectorLayout.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Main content plus optional trailing inspector using native macOS `.inspector`.
struct CareerTrailingInspectorLayout<Main: View, Inspector: View>: View {
    @Binding var isInspectorPresented: Bool
    var inspectorWidth: CGFloat = 380
    var reduceMotion: Bool = false
    @ViewBuilder var main: () -> Main
    @ViewBuilder var inspector: () -> Inspector

    var body: some View {
        main()
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $isInspectorPresented) {
                inspector()
                    .inspectorColumnWidth(min: inspectorWidth, ideal: inspectorWidth, max: inspectorWidth + 120)
            }
            .animation(DesignSystem.Motion.springOrEase(reduceMotion: reduceMotion), value: isInspectorPresented)
    }
}
