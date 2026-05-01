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

// MARK: - SettingsConnectedAppsPanel

struct SettingsConnectedAppsPanel: View {
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @State private var showICloudSheet  = false
    @State private var iCloudUsername   = ""
    @State private var iCloudPassword   = ""
    @State private var iCloudConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Connected Apps")
                .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            SettingsCard(title: "Calendar Integrations", icon: "calendar", iconColor: .blue) {
                // Google Calendar
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
        }
        .frame(maxWidth: 700, alignment: .leading)
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
        .onChange(of: calendarManager.iCloudStatus) { newStatus in
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
    @EnvironmentObject private var securityManager: SecurityManager
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("security.encryptionEnabled") private var encryptionEnabled: Bool = true
    @StateObject private var aiStorageVM = AIStorageViewModel()
    @State private var selectedModelSpec: ModelSpec = .gemma4
    @State private var aiModelErrorText: String?
    @State private var isBackupBusy: Bool = false
    @State private var isPrivacyOverviewPresented: Bool = false
    @State private var isLogsPresented: Bool = false
    @State private var isPerformanceDiagnosticsExpanded: Bool = false
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @AppStorage(RuntimeTelemetryMonitor.enabledKey) private var runtimeTelemetryEnabled: Bool = true
    @AppStorage(RuntimeTelemetryMonitor.heartbeatIntervalKey) private var runtimeTelemetryIntervalSeconds: Int = 1
    @AppStorage(RuntimeTelemetryMonitor.stallThresholdKey) private var runtimeStallThresholdSeconds: Int = 3
    @AppStorage(AssistantWebSearchSettings.searxBaseURLKey) private var searxBaseURL: String = AssistantWebSearchSettings.defaultSearxBaseURL
    @AppStorage(AssistantWebSearchSettings.extraFetchHostsKey) private var extraFetchHostsRaw: String = ""
    @AppStorage(AssistantWebSearchSettings.semanticMemoryEnabledKey) private var semanticWebMemoryEnabled: Bool = false
    @AppStorage("assistant.streaming.enabled") private var assistantStreamingEnabled: Bool = true
    @AppStorage("assistant.runtime.showDiagnostics") private var assistantRuntimeDiagnosticsEnabled: Bool = false
    @AppStorage("assistant.response.lengthPreset") private var assistantResponseLengthPreset: String = "balanced"
    @State private var searxValidationMessage: String?
    @State private var isValidatingSearx: Bool = false
    @State private var showAdvancedWebSearchSettings: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Privacy & Security")
                .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

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

            // MARK: AI & Storage Card
            SettingsCard(title: "AI & Storage", icon: "cpu", iconColor: DesignSystem.Colors.secondary) {
                aiModelRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                modelStatusRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                modelActionsRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                assistantWebSearchSettingsBlock
            }
            .task { await refreshSelectedModelStorage() }
            .onChange(of: selectedModelSpec) { _, _ in
                Task { await refreshSelectedModelStorage() }
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
        .frame(maxWidth: 700, alignment: .leading)
        .sheet(isPresented: $isPrivacyOverviewPresented) {
            PrivacyOverviewView()
                .dismissOnOutsideClickForSheet()
        }
        .onAppear {
            Task { await refreshSelectedModelStorage() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshSelectedModelStorage() }
        }
        #if DEBUG
        .sheet(isPresented: $isLogsPresented) {
            AppLogsView()
                .dismissOnOutsideClickForSheet()
        }
        #endif
    }

    // MARK: - AI Model Row

    private var aiModelRow: some View {
        let spec = selectedModelSpec
        let sizeLabel = aiStorageVM.installedSizeBytes > 0
            ? aiStorageVM.formatBytes(aiStorageVM.installedSizeBytes)
            : "—"
        let descriptorSuffix = aiStorageVM.hasStaleInstallFiles ? " (outdated files detected)" : ""
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Syllabus AI Model")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("\(spec.displayName) · \(sizeLabel)\(descriptorSuffix)")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            Spacer()
            Menu(spec.displayName) {
                Button(ModelSpec.gemma4.displayName) {
                    selectedModelSpec = .gemma4
                }
            }
            .font(DesignSystem.Fonts.main(size: 12))
            .frame(maxWidth: 180)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Model Status Row

    private var modelStatusRow: some View {
        let isInstalled = aiStorageVM.isInstalled
        let hasStale = aiStorageVM.hasStaleInstallFiles
        return HStack {
            Text("Model Status")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            Spacer()
            Circle()
                .fill(isInstalled ? Color.green : (hasStale ? DesignSystem.Colors.warning : Color.orange))
                .frame(width: 7, height: 7)
            Text(isInstalled ? "Installed" : (hasStale ? "Outdated - Re-download Required" : "Not Installed"))
                .font(DesignSystem.Fonts.main(size: 13))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Assistant Web Search & Memory

    private var assistantWebSearchSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assistant Web Search")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)

            Text("Default search: Startpage (configured automatically).")
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundColor(DesignSystem.Colors.textLight)

            DisclosureGroup("Advanced web search settings", isExpanded: $showAdvancedWebSearchSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("SearXNG base URL (HTTPS or localhost HTTP)", text: $searxBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Fonts.main(size: 12))

                    Text("Default: \(AssistantWebSearchSettings.defaultSearxBaseURL) (Startpage engine). Local dev allowed via http://127.0.0.1:PORT.")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    HStack(spacing: 12) {
                        Button(isValidatingSearx ? "Validating…" : "Validate SearXNG") {
                            searxValidationMessage = nil
                            isValidatingSearx = true
                            Task {
                                do {
                                    try await SearXNGClient().validateConfiguration()
                                    await MainActor.run {
                                        searxValidationMessage = "Connection OK."
                                        isValidatingSearx = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        searxValidationMessage = error.localizedDescription
                                        isValidatingSearx = false
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isValidatingSearx || searxBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if let searxValidationMessage, !searxValidationMessage.isEmpty {
                Text(searxValidationMessage)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(searxValidationMessage.contains("OK") ? DesignSystem.Colors.info : DesignSystem.Colors.error)
            }

            Text("Extra fetch hosts (comma-separated)")
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
                .padding(.top, 4)

            TextField("e.g. www.example.edu, example.org", text: $extraFetchHostsRaw)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.main(size: 12))

            SToggleRow(
                label: "Semantic web memory",
                subtitle: "Stores compact on-device vectors for hybrid retrieval with your message (FTS + cosine). Uses a fast lexical sketch until a dedicated MLX embedding model is added.",
                isOn: $semanticWebMemoryEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SToggleRow(
                label: "Stream assistant replies",
                subtitle: "Animate local model replies as they arrive in the chat transcript.",
                isOn: $assistantStreamingEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SToggleRow(
                label: "Assistant runtime diagnostics",
                subtitle: "Show local token/length diagnostics in the assistant transcript footer.",
                isOn: $assistantRuntimeDiagnosticsEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SMenuRow(
                label: "Assistant response length",
                subtitle: "Controls max local reply size before rendering.",
                currentDisplay: assistantResponseLengthLabel,
                options: ["short", "balanced", "detailed"],
                optionLabel: { value in
                    switch value {
                    case "short": return "Short"
                    case "detailed": return "Detailed"
                    default: return "Balanced"
                    }
                },
                onSelect: { value in
                    assistantResponseLengthPreset = value
                }
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var assistantResponseLengthLabel: String {
        switch assistantResponseLengthPreset {
        case "short":
            return "Short"
        case "detailed":
            return "Detailed"
        default:
            return "Balanced"
        }
    }

    // MARK: - Model Actions Row

    private var modelActionsRow: some View {
        let isInstalled = aiStorageVM.isInstalled
        let hasLocalFiles = aiStorageVM.installedSizeBytes > 0
        let hasStale = aiStorageVM.hasStaleInstallFiles
        return VStack(alignment: .leading, spacing: 10) {
            if aiStorageVM.isWorking {
                VStack(alignment: .leading, spacing: 6) {
                    Text(aiStorageVM.detail)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    ProgressView(value: aiStorageVM.progress)
                        .progressViewStyle(.linear)
                }
            }

            if let aiModelErrorText {
                Text(aiModelErrorText)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.error)
            }

            if hasStale {
                Text("Existing model files do not match the current Gemma spec. Use Repair Download to refresh.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.warning)
            }

            HStack(spacing: 12) {
                Button(isInstalled ? "Re-Download" : (hasStale ? "Repair Download" : "Download")) {
                    Task { await installSelectedModel() }
                }
                .buttonStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)
                .disabled(aiStorageVM.isWorking)

                if hasLocalFiles {
                    Button("Delete Model") {
                        Task { await deleteSelectedModel() }
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.error)
                    .disabled(aiStorageVM.isWorking)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
                        .onChange(of: runtimeTelemetryIntervalSeconds) { _ in
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
                        .onChange(of: runtimeStallThresholdSeconds) { _ in
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
        .onChange(of: isPerformanceDiagnosticsExpanded) { expanded in
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
            try? DataWipeManager.wipeAllDataAndExit(coreData: CoreDataManager.shared)
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
            defer { Task { @MainActor in isBackupBusy = false } }
            do {
                try AppBackupManager.exportBackup(to: url)
                await MainActor.run {
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Exported",
                        message: "Your data was saved successfully."
                    )
                }
            } catch {
                await MainActor.run {
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
            defer { Task { @MainActor in isBackupBusy = false } }
            do {
                try AppBackupManager.importBackup(from: url)
                await MainActor.run {
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Imported",
                        message: "Your data was restored successfully."
                    )
                }
            } catch {
                await MainActor.run {
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Import Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    @MainActor
    private func refreshSelectedModelStorage() async {
        aiModelErrorText = nil
        await aiStorageVM.refreshSize(for: selectedModelSpec)
    }

    @MainActor
    private func installSelectedModel() async {
        aiModelErrorText = nil
        do {
            try await aiStorageVM.ensureInstalled(spec: selectedModelSpec)
            await aiStorageVM.refreshSize(for: selectedModelSpec)
            UserDefaults.standard.set(true, forKey: "assistant.localLLM.enabled")
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Model Installed",
                message: "\(selectedModelSpec.displayName) is ready."
            )
        } catch {
            aiModelErrorText = "Install failed: \(error.localizedDescription)"
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Model Install Failed",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteSelectedModel() async {
        aiModelErrorText = nil
        do {
            try await aiStorageVM.delete(spec: selectedModelSpec)
            await aiStorageVM.refreshSize(for: selectedModelSpec)
            AppNotificationCenter.shared.post(
                kind: .info,
                title: "Model Deleted",
                message: "\(selectedModelSpec.displayName) was removed."
            )
        } catch {
            aiModelErrorText = "Delete failed: \(error.localizedDescription)"
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Model Delete Failed",
                message: error.localizedDescription
            )
        }
    }
}
