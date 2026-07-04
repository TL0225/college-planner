// SettingsPanels_Academics.swift
// Feature: Settings
// Purpose: Settings module — SettingsAcademicsPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct SettingsAcademicsPanel: View {
    @State private var showTrustedSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCatalogSyncSection()

            SettingsCard(
                title: String(localized: "settings.academics.catalog_sources", defaultValue: "Catalog sources"),
                icon: "checkmark.shield",
                iconColor: DesignSystem.Colors.info
            ) {
                SActionRow(
                    label: String(localized: "settings.academics.trusted_sources", defaultValue: "Trusted catalog sources"),
                    subtitle: String(
                        localized: "settings.academics.trusted_sources.help",
                        defaultValue: "Manage which catalog bundles this device trusts."
                    ),
                    actionLabel: String(localized: "settings.academics.trusted_sources.action", defaultValue: "Manage…"),
                    action: { showTrustedSources = true }
                )
            }

            SettingsCard(
                title: String(localized: "settings.academics.alerts", defaultValue: "Alerts"),
                icon: "bell.badge",
                iconColor: DesignSystem.Colors.warning
            ) {
                AcademicsNotificationSettingsRows()
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .sheet(isPresented: $showTrustedSources) {
            CatalogTrustedSourcesView()
                .dismissOnOutsideClickForSheet()
        }
    }
}

private struct AcademicsNotificationSettingsRows: View {
    @AppStorage("notifications.assignmentDue") private var assignmentDue: Bool = true
    @AppStorage("notifications.gradeUpdates") private var gradeUpdates: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            SToggleRow(
                label: String(localized: "settings.academics.assignment_due", defaultValue: "Assignment due reminders"),
                subtitle: String(
                    localized: "settings.academics.assignment_due.help",
                    defaultValue: "Notify when assignments are approaching."
                ),
                isOn: $assignmentDue
            )
            Divider().padding(.horizontal, 18)
            SToggleRow(
                label: String(localized: "settings.academics.grade_updates", defaultValue: "Grade updates"),
                subtitle: String(
                    localized: "settings.academics.grade_updates.help",
                    defaultValue: "Notify when grades change."
                ),
                isOn: $gradeUpdates
            )
        }
    }
}
