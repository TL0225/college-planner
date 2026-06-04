// WatchdogSettingsPanel.swift
// Feature: Settings
// Purpose: Settings module — WatchdogSettingsPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

// MARK: - WatchdogSettingsPanel

struct WatchdogSettingsPanel: View {

    @StateObject private var watchdog         = FSWatchdogService.shared
    @StateObject private var staleMonitor     = StaleFileMonitor.shared
    @StateObject private var screenshotTriage = VaultScreenshotTriage.shared
    @StateObject private var analytics        = VaultStorageAnalytics.shared
    @StateObject private var cloudIntegration = CloudIntegrationService.shared

    @State private var showAddFolderPanel = false
    @State private var showRemoveAlert    = false
    @State private var pathToRemove: String? = nil
    @AppStorage("staleFileThresholdDays") private var thresholdDays: Int = 7

    var body: some View {
        Form {
            // MARK: — File Watchdog status

            Section {
                LabeledContent(
                    watchdog.isWatching
                        ? String(localized: "settings.watchdog.status_active")
                        : String(localized: "settings.watchdog.status_inactive")
                ) {
                    Circle()
                        .fill(watchdog.isWatching ? Color.green : Color.secondary)
                        .frame(width: 10, height: 10)
                }

                if let last = watchdog.lastDetectedFile {
                    LabeledContent(String(localized: "settings.watchdog.last_file_detected")) {
                        Text(last.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(
                    String(localized: "settings.watchdog.card_file_watchdog"),
                    systemImage: "eye.fill"
                )
            }

            // MARK: — Watched folders

            Section {
                if watchdog.watchedPaths.isEmpty {
                    Text(String(localized: "settings.watchdog.empty_folders"))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(watchdog.watchedPaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.blue)
                                .font(.system(size: 13))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                pathToRemove = path
                                showRemoveAlert = true
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color.red)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button {
                        pickFolder()
                    } label: {
                        Label(
                            String(localized: "settings.watchdog.add_folder"),
                            systemImage: "plus.circle"
                        )
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: NSHomeDirectory())
                                .appendingPathComponent("Documents/College")
                        )
                    } label: {
                        Label(
                            String(localized: "settings.watchdog.show_vault"),
                            systemImage: "folder.badge.magnifyingglass"
                        )
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Label(
                    String(localized: "settings.watchdog.card_watched_folders"),
                    systemImage: "folder.badge.questionmark"
                )
            }

            // MARK: — Cloud Integrations (No OAuth)

            Section {
                if cloudIntegration.providers.isEmpty {
                    Text("No cloud provider folders detected yet. Click Scan Providers or grant access manually.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(cloudIntegration.providers) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: providerSymbol(for: provider.kind))
                                    .foregroundStyle(provider.isAuthorized ? Color.green : Color.secondary)
                                    .font(.system(size: 13))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(provider.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(provider.rootPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(provider.statusText)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(provider.needsRegrant ? Color.orange : (provider.isAuthorized ? Color.green : Color.secondary))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }

                            HStack(spacing: 12) {
                                Button(provider.needsRegrant ? "Fix Access" : (provider.isAuthorized ? "Regrant Access" : "Grant Access")) {
                                    grantCloudFolderAccess(for: provider)
                                }
                                .buttonStyle(.borderless)

                                if provider.isAuthorized {
                                    Button("Revoke") {
                                        cloudIntegration.revokeAuthorization(for: provider)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                }
                            }

                            if let summary = cloudIntegration.scanSummary(for: provider) {
                                Text("Indexed \(summary.fileCount) files • latest: \(summary.latestFileName ?? "—")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            if let lastImport = cloudIntegration.lastImportDate(for: provider) {
                                Text("Last import: \(RelativeDateTimeFormatter().localizedString(for: lastImport, relativeTo: Date()))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            if provider.isAuthorized {
                                let authorized = cloudIntegration.authorizedPaths(for: provider)
                                if !authorized.isEmpty {
                                    Text("Authorized: \(authorized.joined(separator: ", ").replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button("Scan Providers") {
                        cloudIntegration.refreshDetectedProviders()
                        cloudIntegration.scanAuthorizedRootsNow()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if let lastScanAt = cloudIntegration.lastScanAt {
                        Text("Last scan: \(RelativeDateTimeFormatter().localizedString(for: lastScanAt, relativeTo: Date()))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Cloud Integrations (No OAuth)", systemImage: "externaldrive.connected.to.line.below")
            } footer: {
                Text("Uses local sync folders + security-scoped access. Supports iCloud, Google Drive, OneDrive, Box, and other providers without OAuth APIs.")
            }

            // MARK: — Stale file monitor

            Section {
                LabeledContent(String(localized: "settings.watchdog.alert_threshold")) {
                    Stepper(
                        String(format: String(localized: "settings.watchdog.stepper_days"), thresholdDays),
                        value: $thresholdDays,
                        in: 1...30
                    )
                    .font(.system(size: 13))
                    .frame(width: 130)
                }

                LabeledContent(String(localized: "settings.watchdog.scan_now")) {
                    Button(String(localized: "settings.watchdog.run_scan")) {
                        Task { await staleMonitor.scanNow() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.blue)
                }

                if staleMonitor.staleFilesDetected > 0 {
                    LabeledContent(String(localized: "settings.watchdog.stale_detected_label")) {
                        Text(String(format: String(localized: "settings.watchdog.stale_detected"), staleMonitor.staleFilesDetected))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(
                    String(localized: "settings.watchdog.card_stale_monitor"),
                    systemImage: "clock.badge.exclamationmark"
                )
            }

            // MARK: — Screenshot triage

            Section {
                Toggle(String(localized: "settings.watchdog.auto_triage"), isOn: $screenshotTriage.isEnabled)

                LabeledContent(String(localized: "settings.watchdog.auto_delete")) {
                    Stepper(
                        String(format: String(localized: "settings.watchdog.stepper_days"), screenshotTriage.autoDeleteDays),
                        value: $screenshotTriage.autoDeleteDays,
                        in: 1...30
                    )
                    .font(.system(size: 13))
                    .frame(width: 130)
                }

                if !screenshotTriage.pendingScreenshots.isEmpty {
                    LabeledContent(String(localized: "settings.watchdog.pending_screenshots")) {
                        Text("\(screenshotTriage.pendingScreenshots.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(
                    String(localized: "settings.watchdog.card_screenshot"),
                    systemImage: "camera.viewfinder"
                )
            }

            // MARK: — Storage analytics

            Section {
                LabeledContent(String(localized: "settings.watchdog.total_vault")) {
                    Text(analytics.formattedSize(analytics.totalVaultBytes))
                        .foregroundStyle(.secondary)
                }

                if analytics.staleFileBytes > 0 {
                    LabeledContent(String(localized: "settings.watchdog.stale_files_label")) {
                        Text(analytics.formattedSize(analytics.staleFileBytes))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent(String(localized: "settings.watchdog.refresh_analytics")) {
                    Button(
                        analytics.isRefreshing
                            ? String(localized: "settings.watchdog.refreshing")
                            : String(localized: "settings.watchdog.refresh")
                    ) {
                        guard !analytics.isRefreshing else { return }
                        Task { await analytics.refresh() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(analytics.isRefreshing ? Color.secondary : Color.blue)
                    .disabled(analytics.isRefreshing)
                }
            } header: {
                Label(
                    String(localized: "settings.watchdog.card_storage"),
                    systemImage: "chart.pie.fill"
                )
            }
        }
        .formStyle(.grouped)
        .alert(
            String(localized: "settings.watchdog.remove_folder_title"),
            isPresented: $showRemoveAlert,
            presenting: pathToRemove
        ) { path in
            Button(String(localized: "common.remove"), role: .destructive) {
                watchdog.removeWatchedPath(path)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { path in
            Text(String(format: String(localized: "settings.watchdog.remove_folder_message"),
                        URL(fileURLWithPath: path).lastPathComponent))
        }
        .task {
            await analytics.refresh()
            cloudIntegration.refreshDetectedProviders()
            cloudIntegration.scanAuthorizedRootsNow()
        }
    }

    // MARK: - Folder Picker

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt  = String(localized: "settings.watchdog.folder_picker_prompt")
        panel.message = String(localized: "settings.watchdog.folder_picker_message")

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            Task { @MainActor in
                watchdog.addWatchedPath(url.path)
                _ = CollegePersistence.shared.addWatchedFolder(path: url.path, bookmarkData: bookmarkData)
            }
        }
    }

    private func grantCloudFolderAccess(for provider: CloudIntegrationService.Provider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = cloudIntegration.suggestedDirectoryURL(for: provider)
        panel.prompt = "Grant Access"
        panel.message = "Choose a folder inside \(provider.displayName) for College to scan and import."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            Task { @MainActor in
                let path = (url.path as NSString).standardizingPath
                FSWatchdogService.shared.storeSecurityBookmark(for: url)
                FSWatchdogService.shared.addWatchedPath(path)
                _ = CollegePersistence.shared.addWatchedFolder(path: path, bookmarkData: bookmarkData)
                cloudIntegration.refreshDetectedProviders()
            }
        }
    }

    private func providerSymbol(for kind: CloudIntegrationService.Provider.Kind) -> String {
        switch kind {
        case .iCloudDrive:
            return "icloud"
        case .googleDrive:
            return "g.circle"
        case .oneDrive:
            return "1.circle"
        case .boxDrive:
            return "shippingbox"
        case .dropbox:
            return "archivebox"
        case .generic:
            return "externaldrive"
        }
    }
}
