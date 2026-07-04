// CareerApplySavePasswordSheet.swift
// Feature: Career / Apply
// Purpose: Optional save portal password to shared WebPortal keychain.

import SwiftUI

struct CareerApplySavePasswordSheet: View {
    let host: String
    let username: String
    @Binding var password: String
    let onSave: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save password for \(host)?")
                .font(.headline)
            Text("Store credentials in College for this apply portal host.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(username)
                .font(.body.weight(.medium))
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Not now", role: .cancel, action: onSkip)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
