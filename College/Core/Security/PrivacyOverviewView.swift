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
                    sectionTitle("Student education records (FERPA)")
                    Text("College stores your academic records on this Mac only — grades, course plans, transcripts, and career application notes. We do not sell student data or upload your full database to our servers.")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                    bullet(
                        "Your responsibility",
                        detail: "If you share this Mac or backup files, protect them like any sensitive school record. Use Require Unlock in Settings and macOS FileVault for disk-level protection."
                    )

                    Divider().padding(.vertical, 6)

                    sectionTitle("Stored on this Mac")
                    bullet(
                        "local store database (app container)",
                        detail: "Profile, grades, course plans, calendars. Per ADR 008, sensitive fields are stored on disk without full-database encryption in this release; the master key in Keychain still protects backup export."
                    )
                    bullet(
                        "Document Vault (app container)",
                        detail: "Uploaded files live in the app container. Vault files may use a .colenc extension; at-rest encryption ships in a future release (see ADR 008)."
                    )
                    bullet("Keychain", detail: "OAuth tokens. Master encryption key is protected by Touch ID/password.")
                    bullet(
                        "Share extension inbox",
                        detail: "URLs and text you share from Safari land in a shared app-group container (group.com.timothy.college) until the main app imports them into Career."
                    )
                    bullet("Logs & diagnostics", detail: "Redacted logs and diagnostics are stored locally. You can review them in Settings → Privacy & Data → Diagnostics and export a Basic or Full support bundle.")

                    Divider().padding(.vertical, 6)

                    sectionTitle("Sync & backup")
                    bullet(
                        "Local-first (ADR 010)",
                        detail: "Your College database does not automatically sync across devices. Export a .collegebackup file to move data to another Mac."
                    )
                    bullet(
                        "Calendar integrations",
                        detail: "Google or iCloud calendar sync sends event titles, times, and notes to those providers — not your full student record."
                    )

                    Divider().padding(.vertical, 6)

                    sectionTitle("Sent over the network (only when you use features)")
                    bullet("Google OAuth + Google Calendar", detail: "Calendar events you sync (title/location/notes/times) are sent to Google APIs.")
                    bullet("Course catalog scraping", detail: "Fetches public university catalog pages.")
                    bullet("Assistant web search", detail: "When enabled, search queries go to your configured SearX instance — not to College servers.")

                    Divider().padding(.vertical, 6)

                    sectionTitle("Controls")
                    Text("Use Settings → Privacy & Security to lock the app, opt out of anonymous product analytics, and wipe local data.")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
                .padding(DesignSystem.Spacing.lg)
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
                    .foregroundStyle(DesignSystem.Colors.textMain)
                Text("Where your student data lives and what can leave the device.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(DesignSystem.Spacing.md)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
            .foregroundStyle(DesignSystem.Colors.textLight)
            .textCase(.uppercase)
            .padding(.top, 2)
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                Text(detail)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
    }
}

#Preview {
    PrivacyOverviewView()
}
