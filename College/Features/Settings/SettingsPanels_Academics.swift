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

            SettingsCard(title: "Catalog sources", icon: "checkmark.shield", iconColor: .teal) {
                SActionRow(
                    label: "Trusted catalog sources",
                    subtitle: "Manage which catalog bundles this device trusts",
                    actionLabel: "MANAGE",
                    action: { showTrustedSources = true }
                )
            }

            SettingsCard(title: "Alerts", icon: "bell.badge", iconColor: .orange) {
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
                label: "Assignment due reminders",
                subtitle: "Notify when assignments are approaching",
                isOn: $assignmentDue
            )
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            SToggleRow(
                label: "Grade updates",
                subtitle: "Notify when grades change",
                isOn: $gradeUpdates
            )
        }
    }
}
