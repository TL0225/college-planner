// SettingsPanels_App.swift
// Feature: Settings
// Purpose: Settings module — SettingsAppPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

/// Appearance, locale, updates, and global notification preferences.
struct SettingsAppPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsAppearancePanel()

            SettingsAppLocaleAndUpdatesSection()

            SettingsAppNotificationsSection()
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }
}

// MARK: - Locale & updates (from former General panel)

private struct SettingsAppLocaleAndUpdatesSection: View {
    @AppStorage(CalendarTimeZonePreference.storageKey)
    private var calendarTimeZoneSelection: String = CalendarTimeZonePreference.systemValue

    @State private var appUpdateInfo: AppUpdateInfo?
    @State private var appUpdateErrorText: String?
    @State private var isCheckingForAppUpdate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Region & format", icon: "globe", iconColor: DesignSystem.Colors.primary) {
                SRow(
                    label: "Language",
                    subtitle: "Select your preferred interface language",
                    value: "English (US)"
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                timeZoneRow

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SRow(
                    label: "Date Format",
                    subtitle: "How dates are displayed across the portal",
                    value: "MM/DD/YYYY"
                )
            }

            SettingsCard(title: "App Updates", icon: "arrow.down.circle", iconColor: .green) {
                appUpdateRow
            }
        }
    }

    private var appUpdateRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("College")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)

                Text(appUpdateStatusText)
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundColor(appUpdateErrorText == nil ? DesignSystem.Colors.textLight : DesignSystem.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)

                if let appUpdateInfo, appUpdateInfo.isUpdateAvailable, let releaseName = appUpdateInfo.releaseName, !releaseName.isEmpty {
                    Text(releaseName)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if let appUpdateInfo, appUpdateInfo.isUpdateAvailable {
                    Button("DOWNLOAD UPDATE") {
                        NSWorkspace.shared.open(appUpdateInfo.downloadURL)
                    }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .buttonStyle(.plain)
                }

                Button(isCheckingForAppUpdate ? "CHECKING..." : appUpdateInfo == nil ? "CHECK FOR APP UPDATES" : "CHECK AGAIN") {
                    checkForAppUpdates()
                }
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(isCheckingForAppUpdate ? DesignSystem.Colors.textLight : DesignSystem.Colors.primary)
                .buttonStyle(.plain)
                .disabled(isCheckingForAppUpdate)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }

    private var appUpdateStatusText: String {
        if isCheckingForAppUpdate {
            return "Checking GitHub releases..."
        }
        if let appUpdateErrorText {
            return appUpdateErrorText
        }
        guard let appUpdateInfo else {
            return "Current version \(AppUpdateCheckService.currentAppVersion()). Check GitHub for the latest College release."
        }
        if appUpdateInfo.isUpdateAvailable {
            return "Version \(appUpdateInfo.latestVersion) is available. You have \(appUpdateInfo.currentVersion)."
        }
        return "College is up to date. Current version \(appUpdateInfo.currentVersion)."
    }

    private func checkForAppUpdates() {
        guard !isCheckingForAppUpdate else { return }
        isCheckingForAppUpdate = true
        appUpdateErrorText = nil
        Task {
            do {
                let info = try await AppUpdateCheckService.shared.checkForUpdates()
                await MainActor.run {
                    appUpdateInfo = info
                    isCheckingForAppUpdate = false
                }
            } catch {
                await MainActor.run {
                    appUpdateInfo = nil
                    appUpdateErrorText = "Unable to check for updates. Open \(AppUpdateCheckService.repositoryURL.host ?? "GitHub") and try again."
                    isCheckingForAppUpdate = false
                }
            }
        }
    }

    @ViewBuilder
    private var timeZoneRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Zone")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("Your local time for scheduling")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            Spacer()
            Menu {
                Button("Automatic (System)") {
                    calendarTimeZoneSelection = CalendarTimeZonePreference.systemValue
                }
                Divider()
                ForEach(CalendarTimeZonePreference.groupedOptions()) { group in
                    Menu(group.region) {
                        ForEach(group.options) { option in
                            Button {
                                calendarTimeZoneSelection = option.id
                            } label: {
                                Text("\(option.title)  \(option.subtitle)")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedTimeZoneLabel)
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var selectedTimeZoneLabel: String {
        guard calendarTimeZoneSelection != CalendarTimeZonePreference.systemValue else {
            return "Automatic"
        }
        let parts = calendarTimeZoneSelection.split(separator: "/")
        if let last = parts.last {
            return String(last).replacingOccurrences(of: "_", with: " ")
        }
        return calendarTimeZoneSelection
    }
}

// MARK: - Desktop & email alerts (event/academic alerts live in Calendar / Academics)

struct SettingsAppNotificationsSection: View {
    @AppStorage("notifications.desktopAlerts") private var desktopAlerts: Bool = true
    @AppStorage("notifications.emailDigest") private var emailDigest: Bool = false

    var body: some View {
        SettingsCard(title: "Notifications", icon: "bell", iconColor: .orange) {
            SToggleRow(
                label: "Desktop alerts",
                subtitle: "Show banners for important app events",
                isOn: $desktopAlerts
            )
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            SToggleRow(
                label: "Email digest",
                subtitle: "Periodic summary of activity",
                isOn: $emailDigest
            )
        }
    }
}
