// SettingsPanels_Profile.swift
// Feature: Settings
// Purpose: Settings module — SettingsProfilePanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct SettingsProfilePanel: View {
    @Binding var activePage: AppPage
    @AppStorage("account.email") private var accountEmail: String = "Not set"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Identity", icon: "person.crop.circle", iconColor: DesignSystem.Colors.primary) {
                SActionRow(
                    label: "Open Profile",
                    subtitle: "Edit name, degree, portfolio, and progress in the Profile tab",
                    actionLabel: "OPEN",
                    action: { activePage = .profile }
                )
            }

            SettingsCard(title: "Sign-in", icon: "key.fill", iconColor: .orange) {
                SActionRow(
                    label: "Email",
                    subtitle: "Your student account email",
                    actionLabel: "EDIT",
                    action: { editEmail() }
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: "Password",
                    subtitle: "Managed through your institution's portal",
                    actionLabel: "INFO",
                    action: {
                        let alert = NSAlert()
                        alert.messageText = "Password Management"
                        alert.informativeText = "Password management is handled through your institution's portal."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                )
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }

    private func editEmail() {
        let alert = NSAlert()
        alert.messageText = "Edit Email"
        alert.informativeText = "Enter your student account email address."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = accountEmail == "Not set" ? "" : accountEmail
        field.placeholderString = "you@university.edu"
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !entered.isEmpty { accountEmail = entered }
        }
    }
}
