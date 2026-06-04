// CareerTrailingInspectorLayout.swift
// Feature: Career
// Purpose: Career module — CareerTrailingInspectorLayout.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Main content plus optional trailing inspector that slides in from the right (Career Board, Openings, Networking).
struct CareerTrailingInspectorLayout<Main: View, Inspector: View>: View {
    var isInspectorPresented: Bool
    var inspectorWidth: CGFloat = 380
    var reduceMotion: Bool = false
    @ViewBuilder var main: () -> Main
    @ViewBuilder var inspector: () -> Inspector

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            main()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            if isInspectorPresented {
                Divider()

                inspector()
                    .frame(width: inspectorWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(DesignSystem.Motion.springOrEase(reduceMotion: reduceMotion), value: isInspectorPresented)
    }
}
