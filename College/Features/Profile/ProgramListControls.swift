// ProgramListControls.swift
// Feature: Profile
// Purpose: Profile module — ProgramListControls.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Compact add/remove controls for multi-select program lists in profile editors.
struct ProgramListControls: View {
    let canAdd: Bool
    var canRemove: Bool = false
    var addLabel: String? = nil
    let onAdd: () -> Void
    var onRemove: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Label(addLabel ?? "Add", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(!canAdd)

            if canRemove {
                Button(action: onRemove) {
                    Label("Remove", systemImage: "minus")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
