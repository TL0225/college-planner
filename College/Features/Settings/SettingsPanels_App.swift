// SettingsPanels_App.swift
// Feature: Settings
// Purpose: Settings module — SettingsAppPanel.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
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
            SettingsCard(
                title: String(localized: "settings.app.region.card_title", defaultValue: "Region & format"),
                icon: "globe",
                iconColor: DesignSystem.Colors.primary
            ) {
                SRow(
                    label: String(localized: "settings.app.region.language_label", defaultValue: "Language"),
                    subtitle: String(localized: "settings.app.region.language_subtitle", defaultValue: "Select your preferred interface language"),
                    value: String(localized: "settings.app.region.language_value", defaultValue: "English (US)")
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                timeZoneRow

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SRow(
                    label: String(localized: "settings.app.region.date_format_label", defaultValue: "Date Format"),
                    subtitle: String(localized: "settings.app.region.date_format_subtitle", defaultValue: "How dates are displayed across the portal"),
                    value: String(localized: "settings.app.region.date_format_value", defaultValue: "MM/DD/YYYY")
                )
            }

            SettingsCard(
                title: String(localized: "settings.app.updates.card_title", defaultValue: "App Updates"),
                icon: "arrow.down.circle",
                iconColor: .green
            ) {
                SActionRow(
                    label: appUpdateRowLabel,
                    subtitle: appUpdateStatusText,
                    actionLabel: appUpdateCheckActionLabel
                ) {
                    checkForAppUpdates()
                }

                if let appUpdateInfo, appUpdateInfo.isUpdateAvailable {
                    Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                    SActionRow(
                        label: appUpdateDownloadRowLabel,
                        actionLabel: String(localized: "settings.app.updates.download_action", defaultValue: "DOWNLOAD UPDATE")
                    ) {
                        NSWorkspace.shared.open(appUpdateInfo.downloadURL)
                    }
                }
            }
        }
    }

    private var appUpdateRowLabel: String {
        String(localized: "settings.app.updates.app_name", defaultValue: "College")
    }

    private var appUpdateCheckActionLabel: String {
        if isCheckingForAppUpdate {
            return String(localized: "settings.app.updates.checking_action", defaultValue: "CHECKING…")
        }
        if appUpdateInfo == nil {
            return String(localized: "settings.app.updates.check_action", defaultValue: "CHECK FOR APP UPDATES")
        }
        return String(localized: "settings.app.updates.check_again_action", defaultValue: "CHECK AGAIN")
    }

    private var appUpdateDownloadRowLabel: String {
        if let appUpdateInfo, let releaseName = appUpdateInfo.releaseName, !releaseName.isEmpty {
            return releaseName
        }
        return String(localized: "settings.app.updates.update_available_label", defaultValue: "Update available")
    }

    private var appUpdateStatusText: String {
        if isCheckingForAppUpdate {
            return String(localized: "settings.app.updates.status_checking", defaultValue: "Checking GitHub releases…")
        }
        if let appUpdateErrorText {
            return appUpdateErrorText
        }
        guard let appUpdateInfo else {
            return String(localized: "settings.app.updates.status_unknown", defaultValue: "Current version \(AppUpdateCheckService.currentAppVersion()). Check GitHub for the latest College release.")
        }
        if appUpdateInfo.isUpdateAvailable {
            return String(localized: "settings.app.updates.status_available", defaultValue: "Version \(appUpdateInfo.latestVersion) is available. You have \(appUpdateInfo.currentVersion).")
        }
        return String(localized: "settings.app.updates.status_up_to_date", defaultValue: "College is up to date. Current version \(appUpdateInfo.currentVersion).")
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
                    appUpdateErrorText = String(localized: "settings.app.updates.error", defaultValue: "Unable to check for updates. Open \(AppUpdateCheckService.repositoryURL.host ?? "GitHub") and try again.")
                    isCheckingForAppUpdate = false
                }
            }
        }
    }

    @ViewBuilder
    private var timeZoneRow: some View {
        SCustomRow(
            label: String(localized: "settings.app.region.timezone_label", defaultValue: "Time Zone"),
            subtitle: String(localized: "settings.app.region.timezone_subtitle", defaultValue: "Your local time for scheduling")
        ) {
            Menu {
                Button(String(localized: "settings.app.region.timezone_automatic_option", defaultValue: "Automatic (System)")) {
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
                        .foregroundStyle(DesignSystem.Colors.textLight)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var selectedTimeZoneLabel: String {
        guard calendarTimeZoneSelection != CalendarTimeZonePreference.systemValue else {
            return String(localized: "settings.app.region.timezone_automatic", defaultValue: "Automatic")
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
        SettingsCard(
            title: String(localized: "settings.app.notifications.card_title", defaultValue: "Notifications"),
            icon: "bell",
            iconColor: .orange
        ) {
            SToggleRow(
                label: String(localized: "settings.app.notifications.desktop_label", defaultValue: "Desktop alerts"),
                subtitle: String(localized: "settings.app.notifications.desktop_subtitle", defaultValue: "Show banners for important app events"),
                isOn: $desktopAlerts
            )
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            SToggleRow(
                label: String(localized: "settings.app.notifications.digest_label", defaultValue: "Email digest"),
                subtitle: String(localized: "settings.app.notifications.digest_subtitle", defaultValue: "Periodic summary of activity"),
                isOn: $emailDigest
            )
        }
    }
}
