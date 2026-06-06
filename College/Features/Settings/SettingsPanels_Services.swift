// SettingsPanels_Services.swift
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
                .foregroundColor(iconColor)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if isReadOnly {
                    Text("Read only")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }

            Spacer()

            if isSynced, let resync = onResync {
                Button("RE-SYNC") { resync() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .buttonStyle(.plain)
            }

            if let showLog = onShowLog {
                Button("LOG") { showLog() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .buttonStyle(.plain)
            }

            if isSynced {
                if let disconnect = onDisconnect {
                    Button("DISCONNECT") { disconnect() }
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .buttonStyle(.plain)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("CONNECTED")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            } else {
                Button("CONNECT") { onConnect?() }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
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
        Group {
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

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

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

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

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

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

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
                        status: calendarManager.iCloudStatus == .connecting ? "CONNECTING..." : "CONNECT",
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
    private var iCloudCredentialSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect iCloud Calendar")
                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Text("Enter your Apple ID and an **App-Specific Password** from [appleid.apple.com](https://appleid.apple.com).")
                .font(DesignSystem.Fonts.main(size: 13))
                .foregroundColor(DesignSystem.Colors.textLight)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                TextField("Apple ID (email)", text: $iCloudUsername)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                SecureField("App-Specific Password", text: $iCloudPassword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    showICloudSheet = false; iCloudUsername = ""; iCloudPassword = ""
                }
                .buttonStyle(.plain).foregroundColor(DesignSystem.Colors.textLight)

                Button(iCloudConnecting ? "Connecting\u{2026}" : "Connect") {
                    guard !iCloudUsername.isEmpty, !iCloudPassword.isEmpty, !iCloudConnecting else { return }
                    iCloudConnecting = true
                    calendarManager.connectiCloud(username: iCloudUsername, password: iCloudPassword)
                }
                .disabled(iCloudUsername.isEmpty || iCloudPassword.isEmpty || iCloudConnecting)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28).frame(width: 420)
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
}

// MARK: - SettingsPrivacyPanel

struct SettingsPrivacyPanel: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var securityManager: SecurityManager { container.securityManager }
    @AppStorage("security.encryptionEnabled") private var encryptionEnabled: Bool = true
    @State private var isBackupBusy: Bool = false
    @State private var isPrivacyOverviewPresented: Bool = false
    @State private var isLogsPresented: Bool = false
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
            SettingsCard(title: "Security", icon: "lock.shield", iconColor: DesignSystem.Colors.primary) {
                SToggleRow(
                    label: "Require Unlock",
                    subtitle: "Use Touch ID/password to access student data",
                    isOn: Binding(
                        get: { encryptionEnabled },
                        set: { newValue in
                            encryptionEnabled = newValue
                            securityManager.setEncryptionEnabled(newValue)
                        }
                    )
                )

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(label: "Privacy Overview", actionLabel: "VIEW") {
                    isPrivacyOverviewPresented = true
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: "Lock Now",
                    actionLabel: "LOCK",
                    actionColor: DesignSystem.Colors.warning
                ) {
                    securityManager.lock()
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: "Clear All Data",
                    actionLabel: "WIPE",
                    actionColor: DesignSystem.Colors.error
                ) {
                    confirmWipe()
                }
            }

            // MARK: Backup & Restore Card
            SettingsCard(
                title: "Backup & Restore",
                icon: "arrow.clockwise.icloud",
                iconColor: DesignSystem.Colors.info
            ) {
                SActionRow(
                    label: "Export Backup",
                    actionLabel: isBackupBusy ? "WORKING…" : "EXPORT"
                ) {
                    exportBackup()
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: "Import Backup",
                    actionLabel: isBackupBusy ? "WORKING…" : "IMPORT"
                ) {
                    importBackup()
                }
            }

            SettingsPerformanceDiagnosticsCard()

            // MARK: Diagnostics Card (DEBUG only)
            #if DEBUG
            SettingsCard(
                title: "Diagnostics",
                icon: "wrench.and.screwdriver",
                iconColor: .purple
            ) {
                SActionRow(label: "Logs", actionLabel: "OPEN") {
                    isLogsPresented = true
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(label: "Unlock Debug Log", actionLabel: "REVEAL") {
                    UnlockDebugLog.revealInFinder()
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(label: "Console Capture", actionLabel: "ENABLE") {
                    AppLogger.shared.redirectConsoleOutput()
                }

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                runtimeTelemetryRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                performanceDiagnosticsRow
            }
            #endif
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .sheet(isPresented: $isPrivacyOverviewPresented) {
            PrivacyOverviewView()
                .dismissOnOutsideClickForSheet()
        }
        #if DEBUG
        .sheet(isPresented: $isLogsPresented) {
            AppLogsView()
                .dismissOnOutsideClickForSheet()
        }
        #endif
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
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer()
                        Stepper(value: $runtimeTelemetryIntervalSeconds, in: 1...10) {
                            Text("\(runtimeTelemetryIntervalSeconds)s")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        .onChange(of: runtimeTelemetryIntervalSeconds) {
                            RuntimeTelemetryMonitor.shared.reconfigure()
                        }
                    }

                    HStack {
                        Text("Stall Threshold")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer()
                        Stepper(value: $runtimeStallThresholdSeconds, in: 2...30) {
                            Text("\(runtimeStallThresholdSeconds)s")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundColor(DesignSystem.Colors.textMain)
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
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer()
                        Text(String(format: "%.1f%%", performanceMonitor.cpuPercent))
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    HStack {
                        Text("Memory")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer()
                        Text(String(format: "%.1f MB", performanceMonitor.memoryMB))
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                }
                .padding(.top, 8)
            },
            label: {
                Text("Performance Diagnostics")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
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
            try? DataWipeManager.wipeAllDataAndExit(persistence: CollegePersistence.shared)
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
            do {
                try AppBackupManager.exportBackup(to: url)
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
            do {
                try AppBackupManager.importBackup(from: url)
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

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}
