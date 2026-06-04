// PrivacyOverviewView.swift
// Feature: Core
// Purpose: Core module — PrivacyOverviewView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct PrivacyOverviewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Stored on this Mac")
                    bullet("local store database (app container)", detail: "Profile, grades, course plans, calendars. Sensitive blobs are encrypted with your master key.")
                    bullet("Document Vault (app container)", detail: "Uploaded files are stored encrypted-at-rest.")
                    bullet("Keychain", detail: "OAuth tokens. Master encryption key is protected by Touch ID/password.")
                    bullet("Logs", detail: "Redacted logs stored locally. Debug diagnostics are not available in Release builds.")

                    Divider().padding(.vertical, 6)

                    sectionTitle("Sent over the network (only when you use features)")
                    bullet("Google OAuth + Google Calendar", detail: "Calendar events you sync (title/location/notes/times) are sent to Google APIs.")
                    bullet("Course catalog scraping", detail: "Fetches public university catalog pages.")

                    Divider().padding(.vertical, 6)

                    sectionTitle("Controls")
                    Text("Use Settings → Privacy & Security to lock the app and wipe local data.")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(18)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Privacy Overview")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("Where your data lives and what can leave the device.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
            .foregroundColor(DesignSystem.Colors.textLight)
            .textCase(.uppercase)
            .padding(.top, 2)
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text(detail)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
        }
    }
}

#Preview {
    PrivacyOverviewView()
}

