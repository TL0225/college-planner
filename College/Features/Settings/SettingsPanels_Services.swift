// SettingsPanels_Services.swift
import CollegeCalendar
// Feature: Settings
// Purpose: Settings module — ConnectedServiceRow.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

// MARK: - Connected Service Row

private struct ConnectedServiceRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let status: String
    let isSynced: Bool
    var isReadOnly: Bool = false
    var onConnect: (() -> Void)? = nil
    var onDisconnect: (() -> Void)? = nil
    var onResync: (() -> Void)? = nil
    var onShowLog: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                if isReadOnly {
                    Text(String(localized: "settings.services.read_only", defaultValue: "Read only"))
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }

            Spacer()

            if isSynced, let resync = onResync {
                Button(String(localized: "settings.services.resync", defaultValue: "Re-sync")) { resync() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .buttonStyle(.plain)
            }

            if let showLog = onShowLog {
                Button(String(localized: "settings.services.log", defaultValue: "Log")) { showLog() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .buttonStyle(.plain)
            }

            if isSynced {
                if let disconnect = onDisconnect {
                    Button(String(localized: "settings.services.disconnect", defaultValue: "Disconnect")) { disconnect() }
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .buttonStyle(.plain)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(String(localized: "settings.services.connected", defaultValue: "Connected"))
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            } else {
                Button(String(localized: "settings.services.connect", defaultValue: "Connect")) { onConnect?() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .buttonStyle(.plain)
                    .disabled(onConnect == nil)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Calendar connections (embedded in Calendar settings)

struct CalendarConnectionsSettingsSection: View {
    @Environment(AppContainer.self) private var container
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    @State private var showICloudSheet  = false
    @State private var iCloudUsername   = ""
    @State private var iCloudPassword   = ""
    @State private var iCloudConnecting = false

    var body: some View {
        SettingsCard(
            title: String(localized: "settings.calendar.connections_title", defaultValue: "Connected calendars"),
            icon: "link.circle",
            iconColor: DesignSystem.Colors.primary
        ) {
            ConnectedServiceRow(
                icon: "calendar",
                iconColor: .blue,
                name: "Google Calendar",
                status: calendarManager.googleStatus.rawValue,
                isSynced: calendarManager.googleStatus == .connected,
                onConnect: { calendarManager.connectGoogle() },
                onDisconnect: { calendarManager.disconnectGoogle() },
                onResync: { calendarManager.resyncGoogleNow() },
                onShowLog: { GoogleDebugLog.revealInFinder() }
            )

            rowDivider

            // Apple Calendar
            ConnectedServiceRow(
                icon: "apple.logo",
                iconColor: .black,
                name: "Apple Calendar",
                status: calendarManager.appleStatus.rawValue,
                isSynced: calendarManager.appleStatus == .connected,
                onConnect: { calendarManager.connectAppleCalendar() },
                onDisconnect: { calendarManager.disconnectAppleCalendar() },
                onResync: { calendarManager.resyncAppleCalendarNow() }
            )

            rowDivider

            // Outlook Calendar (Microsoft Graph OAuth2)
            ConnectedServiceRow(
                icon: "envelope.fill",
                iconColor: .blue,
                name: "Outlook Calendar",
                status: calendarManager.outlookStatus.rawValue,
                isSynced: calendarManager.outlookStatus == .connected,
                isReadOnly: true,
                onConnect: calendarManager.outlookStatus == .connecting ? nil : { calendarManager.connectOutlook() },
                onDisconnect: { calendarManager.disconnectOutlook() },
                onResync: { calendarManager.resyncOutlookNow() }
            )

            rowDivider

            // iCloud Calendar (CalDAV)
            if calendarManager.iCloudStatus == .connected {
                ConnectedServiceRow(
                    icon: "icloud.fill",
                    iconColor: Color(nsColor: .systemTeal),
                    name: "iCloud Calendar",
                    status: calendarManager.iCloudStatus.rawValue,
                    isSynced: true,
                    isReadOnly: true,
                    onDisconnect: { calendarManager.disconnectiCloud() },
                    onResync: { calendarManager.resyncICloudNow() }
                )
            } else {
                ConnectedServiceRow(
                    icon: "icloud.fill",
                    iconColor: Color(nsColor: .systemTeal),
                    name: "iCloud Calendar",
                    status: calendarManager.iCloudStatus == .connecting
                        ? String(localized: "settings.services.connecting", defaultValue: "Connecting\u{2026}")
                        : String(localized: "settings.services.connect", defaultValue: "Connect"),
                    isSynced: false,
                    isReadOnly: true,
                    onConnect: calendarManager.iCloudStatus == .connecting ? nil : { showICloudSheet = true }
                )
            }
        }
        .sheet(isPresented: $showICloudSheet) {
            iCloudCredentialSheet
                .dismissOnOutsideClickForSheet()
        }
    }

    @ViewBuilder
    private var rowDivider: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.5))
            .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var iCloudCredentialSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "settings.services.icloud.title", defaultValue: "Connect iCloud Calendar"))
                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Text(iCloudInstructions)
                .font(DesignSystem.Fonts.main(size: 13))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                TextField(String(localized: "settings.services.icloud.apple_id", defaultValue: "Apple ID (email)"), text: $iCloudUsername)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                SecureField(String(localized: "settings.services.icloud.app_password", defaultValue: "App-Specific Password"), text: $iCloudPassword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                    showICloudSheet = false; iCloudUsername = ""; iCloudPassword = ""
                }
                .buttonStyle(.plain).foregroundStyle(DesignSystem.Colors.textLight)

                Button(iCloudConnecting
                    ? String(localized: "settings.services.connecting", defaultValue: "Connecting\u{2026}")
                    : String(localized: "settings.services.connect", defaultValue: "Connect")) {
                    guard !iCloudUsername.isEmpty, !iCloudPassword.isEmpty, !iCloudConnecting else { return }
                    iCloudConnecting = true
                    calendarManager.connectiCloud(username: iCloudUsername, password: iCloudPassword)
                }
                .disabled(iCloudUsername.isEmpty || iCloudPassword.isEmpty || iCloudConnecting)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.xxl).frame(width: 420)
        .onChange(of: calendarManager.iCloudStatus) { _, newStatus in
            if newStatus == .connected {
                // Connection succeeded — close the sheet.
                showICloudSheet = false
                iCloudUsername = ""
                iCloudPassword = ""
                iCloudConnecting = false
            } else if newStatus == .disconnected && iCloudConnecting {
                // Connection failed — stay open so the user can correct credentials.
                iCloudConnecting = false
            }
        }
    }

    private var iCloudInstructions: AttributedString {
        let raw = String(
            localized: "settings.services.icloud.instructions",
            defaultValue: "Enter your Apple ID and an **App-Specific Password** from [appleid.apple.com](https://appleid.apple.com)."
        )
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}

// MARK: - SettingsPrivacyPanel

struct SettingsPrivacyPanel: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var securityManager: SecurityManager { container.securityManager }
    @AppStorage("security.encryptionEnabled") private var encryptionEnabled: Bool = true
    @AppStorage(ProductAnalytics.optInKey) private var productAnalyticsOptIn: Bool = false
    @State private var isBackupBusy: Bool = false
    @State private var isPrivacyOverviewPresented: Bool = false
    @State private var isDiagnosticsPresented: Bool = false
    #if DEBUG
    @State private var isPerformanceDiagnosticsExpanded: Bool = false
    @State private var performanceMonitor = PerformanceMonitor()
    @AppStorage(RuntimeTelemetryMonitor.enabledKey) private var runtimeTelemetryEnabled: Bool = true
    @AppStorage(RuntimeTelemetryMonitor.heartbeatIntervalKey) private var runtimeTelemetryIntervalSeconds: Int = 1
    @AppStorage(RuntimeTelemetryMonitor.stallThresholdKey) private var runtimeStallThresholdSeconds: Int = 3
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: Security Card
            SettingsCard(
                title: String(localized: "settings.privacy.security_title", defaultValue: "Security"),
                icon: "lock.shield",
                iconColor: DesignSystem.Colors.primary
            ) {
                SToggleRow(
                    label: String(localized: "settings.privacy.require_unlock", defaultValue: "Require Unlock"),
                    subtitle: String(localized: "settings.privacy.require_unlock_sub", defaultValue: "Lock screen with Touch ID/password. Full-disk database encryption ships in a future release (ADR 008)."),
                    isOn: Binding(
                        get: { encryptionEnabled },
                        set: { newValue in
                            encryptionEnabled = newValue
                            securityManager.setEncryptionEnabled(newValue)
                        }
                    )
                )

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.manage_credentials", defaultValue: "Manage Credentials"),
                    subtitle: String(localized: "settings.privacy.manage_credentials_sub", defaultValue: "Review stored passwords in Keychain Access"),
                    actionLabel: String(localized: "settings.privacy.action.manage", defaultValue: "Manage\u{2026}")
                ) {
                    manageCredentials()
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.privacy_overview", defaultValue: "Privacy Overview"),
                    actionLabel: String(localized: "settings.privacy.action.view", defaultValue: "View\u{2026}")
                ) {
                    isPrivacyOverviewPresented = true
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.lock_now", defaultValue: "Lock Now"),
                    actionLabel: String(localized: "settings.privacy.action.lock", defaultValue: "Lock"),
                    actionColor: DesignSystem.Colors.warning
                ) {
                    securityManager.lock()
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.clear_all_data", defaultValue: "Clear All Data"),
                    actionLabel: String(localized: "settings.privacy.action.wipe", defaultValue: "Wipe\u{2026}"),
                    actionColor: DesignSystem.Colors.error
                ) {
                    confirmWipe()
                }
            }

            // MARK: Backup & Restore Card
            SettingsCard(
                title: String(localized: "settings.privacy.backup_title", defaultValue: "Backup & Restore"),
                icon: "arrow.clockwise.icloud",
                iconColor: DesignSystem.Colors.info
            ) {
                SActionRow(
                    label: String(localized: "settings.privacy.export_backup", defaultValue: "Export Backup"),
                    actionLabel: isBackupBusy
                        ? String(localized: "settings.privacy.action.working", defaultValue: "Working\u{2026}")
                        : String(localized: "settings.privacy.action.export", defaultValue: "Export\u{2026}")
                ) {
                    AppFileMenuActions.exportBackup()
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.import_backup", defaultValue: "Import Backup"),
                    actionLabel: isBackupBusy
                        ? String(localized: "settings.privacy.action.working", defaultValue: "Working\u{2026}")
                        : String(localized: "settings.privacy.action.import", defaultValue: "Import\u{2026}")
                ) {
                    AppFileMenuActions.importBackup()
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.view_backups", defaultValue: "View Backups"),
                    subtitle: String(localized: "settings.privacy.view_backups_sub", defaultValue: "Reveal saved backups in Finder"),
                    actionLabel: String(localized: "settings.privacy.action.reveal", defaultValue: "Reveal\u{2026}")
                ) {
                    viewBackups()
                }

                rowDivider

                SActionRow(
                    label: String(localized: "settings.privacy.delete_backups", defaultValue: "Delete Backups"),
                    subtitle: String(localized: "settings.privacy.delete_backups_sub", defaultValue: "Remove all locally stored backups"),
                    actionLabel: String(localized: "settings.privacy.action.delete", defaultValue: "Delete\u{2026}"),
                    actionColor: DesignSystem.Colors.error
                ) {
                    deleteBackups()
                }
            }

            #if DEBUG
            SettingsPerformanceDiagnosticsCard()
            #endif

            SettingsCard(
                title: String(localized: "settings.privacy.analytics_title", defaultValue: "Product Analytics"),
                icon: "chart.bar.doc.horizontal",
                iconColor: DesignSystem.Colors.info
            ) {
                SToggleRow(
                    label: String(localized: "settings.privacy.analytics_opt_in", defaultValue: "Share Anonymous Usage Events"),
                    subtitle: String(localized: "settings.privacy.analytics_opt_in_sub", defaultValue: "Opt-in funnel events (onboarding, page visits, backups). Never includes grades or message text."),
                    isOn: Binding(
                        get: { productAnalyticsOptIn },
                        set: { newValue in
                            productAnalyticsOptIn = newValue
                            ProductAnalytics.setOptedIn(newValue)
                        }
                    )
                )
            }

            SettingsCard(
                title: String(localized: "settings.privacy.diagnostics_title", defaultValue: "Diagnostics"),
                icon: "heart.text.square",
                iconColor: .purple
            ) {
                SActionRow(
                    label: String(localized: "settings.privacy.diagnostics_center", defaultValue: "Diagnostics Center"),
                    subtitle: String(localized: "settings.privacy.diagnostics_center_sub", defaultValue: "Health, logs, crashes, and exportable support bundles"),
                    actionLabel: String(localized: "settings.privacy.action.open", defaultValue: "Open\u{2026}")
                ) {
                    isDiagnosticsPresented = true
                }

                #if DEBUG
                rowDivider
                runtimeTelemetryRow
                rowDivider
                performanceDiagnosticsRow
                #endif
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .sheet(isPresented: $isPrivacyOverviewPresented) {
            PrivacyOverviewView()
                .dismissOnOutsideClickForSheet()
        }
        .sheet(isPresented: $isDiagnosticsPresented) {
            DiagnosticsCenterView()
                .appContainerEnvironment(container)
                .dismissOnOutsideClickForSheet()
        }
    }

    @ViewBuilder
    private var rowDivider: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.5))
            .padding(.horizontal, 18)
    }

    // MARK: - Performance Diagnostics Row (DEBUG)

    #if DEBUG
    private var runtimeTelemetryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SToggleRow(
                label: "Runtime Telemetry",
                subtitle: "Emit heartbeat logs and detect main-thread stalls",
                isOn: Binding(
                    get: { runtimeTelemetryEnabled },
                    set: { newValue in
                        runtimeTelemetryEnabled = newValue
                        RuntimeTelemetryMonitor.shared.reconfigure()
                    }
                )
            )

            if runtimeTelemetryEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Heartbeat")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer()
                        Stepper(value: $runtimeTelemetryIntervalSeconds, in: 1...10) {
                            Text("\(runtimeTelemetryIntervalSeconds)s")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                        }
                        .onChange(of: runtimeTelemetryIntervalSeconds) {
                            RuntimeTelemetryMonitor.shared.reconfigure()
                        }
                    }

                    HStack {
                        Text("Stall Threshold")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer()
                        Stepper(value: $runtimeStallThresholdSeconds, in: 2...30) {
                            Text("\(runtimeStallThresholdSeconds)s")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                        }
                        .onChange(of: runtimeStallThresholdSeconds) {
                            RuntimeTelemetryMonitor.shared.reconfigure()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }

    private var performanceDiagnosticsRow: some View {
        DisclosureGroup(
            isExpanded: $isPerformanceDiagnosticsExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CPU")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer()
                        Text(String(format: "%.1f%%", performanceMonitor.cpuPercent))
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                    }
                    HStack {
                        Text("Memory")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        Spacer()
                        Text(String(format: "%.1f MB", performanceMonitor.memoryMB))
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                    }
                }
                .padding(.top, 8)
            },
            label: {
                Text("Performance Diagnostics")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
            }
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .onChange(of: isPerformanceDiagnosticsExpanded) { _, expanded in
            if expanded { performanceMonitor.start() } else { performanceMonitor.stop() }
        }
    }
    #endif

    // MARK: - Wipe Confirmation

    private func confirmWipe() {
        let alert = NSAlert()
        alert.messageText = "Wipe All Data?"
        alert.informativeText = "This will permanently delete all your data and exit the app. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Wipe & Exit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await BackgroundServiceOnDemand.run(id: "data_wipe") {
                    try? DataWipeManager.wipeAllDataAndExit(persistence: CollegePersistence.shared)
                }
            }
        }
    }

    // MARK: - Export Backup

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.nameFieldStringValue = "CollegeBackup-\(formattedDate()).collegebackup"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBackupBusy = true
        Task {
            defer { isBackupBusy = false }
            await BackgroundServiceOnDemand.run(id: "app_backup_export") {
                do {
                    try await AppBackupManager.exportBackup(to: url)
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Exported",
                        message: "Your data was saved successfully."
                    )
                } catch {
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Export Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Import Backup

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Import Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        isBackupBusy = true
        Task {
            defer { isBackupBusy = false }
            await BackgroundServiceOnDemand.run(id: "app_backup_import") {
                do {
                    try await AppBackupManager.importBackup(from: url)
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Imported",
                        message: "Your data was restored successfully."
                    )
                } catch {
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Import Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Manage Credentials

    private func manageCredentials() {
        let keychainAccess = URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app")
        if FileManager.default.fileExists(atPath: keychainAccess.path) {
            NSWorkspace.shared.open(keychainAccess)
        } else {
            let alert = NSAlert()
            alert.messageText = String(localized: "settings.privacy.credentials.unavailable_title", defaultValue: "Keychain Access Unavailable")
            alert.informativeText = String(localized: "settings.privacy.credentials.unavailable_message", defaultValue: "Open Keychain Access from Applications ▸ Utilities to review stored credentials.")
            alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
            alert.runModal()
        }
    }

    // MARK: - Backups Directory

    private static func backupsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("College/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func viewBackups() {
        do {
            let dir = try Self.backupsDirectory()
            NSWorkspace.shared.open(dir)
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: String(localized: "settings.privacy.backups.open_failed_title", defaultValue: "Couldn't Open Backups"),
                message: error.localizedDescription
            )
        }
    }

    private func deleteBackups() {
        let dir: URL
        do {
            dir = try Self.backupsDirectory()
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: String(localized: "settings.privacy.backups.delete_failed_title", defaultValue: "Couldn't Delete Backups"),
                message: error.localizedDescription
            )
            return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        guard !contents.isEmpty else {
            AppNotificationCenter.shared.post(
                kind: .info,
                title: String(localized: "settings.privacy.backups.none_title", defaultValue: "No Backups Found"),
                message: String(localized: "settings.privacy.backups.none_message", defaultValue: "There are no locally stored backups to delete.")
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "settings.privacy.backups.delete_confirm_title", defaultValue: "Delete All Backups?")
        alert.informativeText = String(localized: "settings.privacy.backups.delete_confirm_message", defaultValue: "This will permanently remove all locally stored backups. This action cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "settings.privacy.backups.delete_confirm_button", defaultValue: "Delete"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }

        AppNotificationCenter.shared.post(
            kind: .success,
            title: String(localized: "settings.privacy.backups.deleted_title", defaultValue: "Backups Deleted"),
            message: String(localized: "settings.privacy.backups.deleted_message", defaultValue: "All locally stored backups were removed.")
        )
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}
