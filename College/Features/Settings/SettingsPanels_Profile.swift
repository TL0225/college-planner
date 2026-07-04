// SettingsPanels_Profile.swift
// Feature: Settings
// Purpose: Settings module — SettingsProfilePanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct SettingsProfilePanel: View {
    @Binding var activePage: AppPage
    @AppStorage("account.email") private var accountEmail: String = ""

    private var emailDisplay: String {
        let trimmed = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "settings.profile.email.not_set", defaultValue: "Not set")
            : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            SettingsCard(
                title: String(localized: "settings.profile.identity", defaultValue: "Identity"),
                icon: "person.crop.circle",
                iconColor: DesignSystem.Colors.primary
            ) {
                SActionRow(
                    label: String(localized: "settings.profile.open", defaultValue: "Open profile"),
                    subtitle: String(
                        localized: "settings.profile.open.help",
                        defaultValue: "Edit name, degree, portfolio, and progress in the Profile tab."
                    ),
                    actionLabel: String(localized: "settings.profile.open.action", defaultValue: "Open"),
                    action: { activePage = .profile }
                )

                Divider().padding(.horizontal, 18)

                SRow(
                    label: String(localized: "settings.profile.account_status", defaultValue: "Account status"),
                    subtitle: String(
                        localized: "settings.profile.account_status.help",
                        defaultValue: "Your local student profile in this app."
                    ),
                    value: String(localized: "settings.profile.account_status.active", defaultValue: "Active")
                )
            }

            SettingsCard(
                title: String(localized: "settings.profile.sign_in", defaultValue: "Sign-in"),
                icon: "key.fill",
                iconColor: DesignSystem.Colors.warning
            ) {
                SRow(
                    label: String(localized: "settings.profile.email", defaultValue: "Email"),
                    subtitle: String(
                        localized: "settings.profile.email.help",
                        defaultValue: "Your student account email."
                    ),
                    value: emailDisplay,
                    valueSelectable: true
                )

                Divider().padding(.horizontal, 18)

                SActionRow(
                    label: String(localized: "settings.profile.edit_email", defaultValue: "Edit email"),
                    actionLabel: String(localized: "settings.profile.edit_email.action", defaultValue: "Edit…"),
                    action: editEmail
                )

                Divider().padding(.horizontal, 18)

                SActionRow(
                    label: String(localized: "settings.profile.institution_portal", defaultValue: "Institution portal"),
                    subtitle: String(
                        localized: "settings.profile.institution_portal.help",
                        defaultValue: "Manage your password through your school's portal."
                    ),
                    actionLabel: String(localized: "settings.profile.open_portal", defaultValue: "Open…"),
                    action: openInstitutionPortal
                )

                Divider().padding(.horizontal, 18)

                SActionRow(
                    label: String(localized: "settings.profile.sign_out", defaultValue: "Sign out"),
                    subtitle: String(
                        localized: "settings.profile.sign_out.help",
                        defaultValue: "Clears local account email from this device."
                    ),
                    actionLabel: String(localized: "settings.profile.sign_out.action", defaultValue: "Sign out"),
                    actionColor: DesignSystem.Colors.error,
                    role: .destructive,
                    action: signOut
                )
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }

    private func editEmail() {
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.profile.edit_email.alert.title", defaultValue: "Edit email")
        alert.informativeText = String(
            localized: "settings.profile.edit_email.alert.message",
            defaultValue: "Enter your student account email address."
        )
        alert.addButton(withTitle: String(localized: "common.save", defaultValue: "Save"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = accountEmail
        field.placeholderString = "you@university.edu"
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            accountEmail = entered
        }
    }

    private func openInstitutionPortal() {
        if let url = LMSPortalConfiguration.resolvedPortalURL() {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.profile.portal_missing.title", defaultValue: "No portal configured")
        alert.informativeText = String(
            localized: "settings.profile.portal_missing.message",
            defaultValue: "Add your learning management system portal URL in LMS settings first."
        )
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        alert.runModal()
    }

    private func signOut() {
        accountEmail = ""
    }
}
