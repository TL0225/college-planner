// SettingsPanels_General.swift
// Feature: Settings
// Purpose: Settings module — SettingsGeneralPanel.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI
import AppKit

// MARK: - General Panel

struct SettingsGeneralPanel: View {
    // Time Zone
    @AppStorage(CalendarTimeZonePreference.storageKey)
    private var calendarTimeZoneSelection: String = CalendarTimeZonePreference.systemValue

    // Calendar preferences
    @AppStorage("calendar.startWeekOn")   private var startWeekOn: String = "Sunday"
    @AppStorage("calendar.defaultDuration") private var defaultDuration: String = "30 min"
    @AppStorage("calendar.showWeekends")  private var showWeekends: Bool = true
    @AppStorage("calendar.showDeclined")  private var showDeclined: Bool = false

    @State private var appUpdateInfo: AppUpdateInfo?
    @State private var appUpdateErrorText: String?
    @State private var isCheckingForAppUpdate = false

    private let weekStartOptions   = ["Sunday", "Monday", "Saturday"]
    private let durationOptions    = ["15 min", "30 min", "45 min", "1 hour", "2 hours"]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            Text("General")
                .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            // Card 1 — General
            SettingsCard(title: "General", icon: "slider.horizontal.3", iconColor: DesignSystem.Colors.primary) {
                SRow(label: "Language",
                     subtitle: "Select your preferred interface language",
                     value: "English (US)")

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                timeZoneRow

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SRow(label: "Date Format",
                     subtitle: "How dates are displayed across the portal",
                     value: "MM/DD/YYYY")
            }

            SettingsCard(title: "App Updates", icon: "arrow.down.circle", iconColor: .green) {
                appUpdateRow
            }

            // Card 2 — Calendar
            SettingsCard(title: "Calendar", icon: "calendar", iconColor: .blue) {
                SMenuRow(
                    label: "Start week on",
                    currentDisplay: startWeekOn,
                    options: weekStartOptions,
                    optionLabel: { $0 },
                    onSelect: { startWeekOn = $0 }
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SMenuRow(
                    label: "Default duration",
                    currentDisplay: defaultDuration,
                    options: durationOptions,
                    optionLabel: { $0 },
                    onSelect: { defaultDuration = $0 }
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SToggleRow(label: "Show weekends", isOn: $showWeekends)

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SToggleRow(label: "Show declined", isOn: $showDeclined)
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
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
                    .accessibilityIdentifier("settings.appUpdates.downloadButton")
                }

                Button(isCheckingForAppUpdate ? "CHECKING..." : appUpdateInfo == nil ? "CHECK FOR APP UPDATES" : "CHECK AGAIN") {
                    checkForAppUpdates()
                }
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(isCheckingForAppUpdate ? DesignSystem.Colors.textLight : DesignSystem.Colors.primary)
                .buttonStyle(.plain)
                .disabled(isCheckingForAppUpdate)
                .accessibilityIdentifier("settings.appUpdates.checkButton")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
        .accessibilityIdentifier("settings.appUpdates.row")
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

    // MARK: Time Zone Row (custom — grouped nested menu)

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
                // "Automatic" system option
                Button("Automatic (System)") {
                    calendarTimeZoneSelection = CalendarTimeZonePreference.systemValue
                }
                Divider()
                // Grouped regions
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

// MARK: - Account Panel

struct SettingsAccountPanel: View {
    @AppStorage("account.email") private var accountEmail: String = "Not set"

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            Text("Account")
                .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            // Card — Account
            SettingsCard(title: "Account", icon: "person.circle", iconColor: DesignSystem.Colors.primary) {
                SActionRow(
                    label: "Email",
                    subtitle: "Your student account email",
                    actionLabel: "EDIT"
                ) {
                    // Present a simple edit alert
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

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: "Password",
                    subtitle: "Last changed: Never",
                    actionLabel: "UPDATE"
                ) {
                    let alert = NSAlert()
                    alert.messageText = "Password Management"
                    alert.informativeText = "Password management is handled through your institution's portal."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
        .frame(maxWidth: 700, alignment: .leading)
    }
}
