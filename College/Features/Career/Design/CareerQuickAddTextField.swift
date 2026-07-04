// CareerQuickAddTextField.swift
// Feature: Career
// Purpose: Career module — CareerQuickAddTextField.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerQuickAddTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        TextField("Quick add company", text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CareerKanbanTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            .onSubmit {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onSubmit()
                text = ""
            }
            .submitLabel(.done)
    }
}
