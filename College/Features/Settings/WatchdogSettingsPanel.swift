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

    @State private var showRemoveAlert    = false
    @State private var pathToRemove: String? = nil
    @AppStorage("staleFileThresholdDays") private var thresholdDays: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            fileWatchdogCard
            watchedFoldersCard
            cloudStorageCard
            staleMonitorCard
            screenshotTriageCard
            storageAnalyticsCard
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .confirmationDialog(
            String(localized: "settings.watchdog.remove_folder_title"),
            isPresented: $showRemoveAlert,
            titleVisibility: .visible,
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

    // MARK: - File Watchdog

    private var fileWatchdogCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_file_watchdog"),
            icon: "eye.fill",
            iconColor: DesignSystem.Colors.primary
        ) {
            SLabeledRow(
                label: watchdog.isWatching
                    ? String(localized: "settings.watchdog.status_active")
                    : String(localized: "settings.watchdog.status_inactive")
            ) {
                Circle()
                    .fill(watchdog.isWatching ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
            }

            if let last = watchdog.lastDetectedFile {
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                SRow(
                    label: String(localized: "settings.watchdog.last_file_detected"),
                    value: last.lastPathComponent
                )
            }
        }
    }

    // MARK: - Watched folders

    private var watchedFoldersCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_watched_folders"),
            icon: "folder.badge.questionmark",
            iconColor: DesignSystem.Colors.info
        ) {
            if watchdog.watchedPaths.isEmpty {
                SettingsInfoRow(text: String(localized: "settings.watchdog.empty_folders"))
            } else {
                ForEach(Array(watchdog.watchedPaths.enumerated()), id: \.element) { index, path in
                    if index > 0 {
                        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                    }
                    watchedFolderRow(path: path)
                }
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            HStack {
                Button {
                    pickFolder()
                } label: {
                    Label(
                        String(localized: "settings.watchdog.add_folder"),
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.primary)

                Spacer()

                Button {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: NSHomeDirectory())
                            .appendingPathComponent("Documents/College")
                    )
                } label: {
                    Label(
                        String(localized: "settings.watchdog.show_vault"),
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(DesignSystem.Fonts.caption1(weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func watchedFolderRow(path: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.blue)
                .font(DesignSystem.Fonts.main(size: 14))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(DesignSystem.Fonts.body(weight: .medium))
                    .foregroundStyle(.primary)
                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(DesignSystem.Fonts.caption2())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                pathToRemove = path
                showRemoveAlert = true
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(DesignSystem.Colors.error)
                    .font(DesignSystem.Fonts.main(size: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Cloud Storage

    private var cloudStorageCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_cloud_storage", defaultValue: "Cloud Storage"),
            icon: "externaldrive.connected.to.line.below",
            iconColor: DesignSystem.Colors.info
        ) {
            if cloudIntegration.providers.isEmpty {
                SettingsInfoRow(
                    text: String(
                        localized: "settings.watchdog.cloud.empty",
                        defaultValue: "No cloud provider folders detected yet. Click Scan Providers or grant access manually."
                    )
                )
            } else {
                ForEach(Array(cloudIntegration.providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                    }
                    cloudProviderRow(provider: provider)
                }
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            HStack {
                Button(String(localized: "settings.watchdog.cloud.scan_providers", defaultValue: "Scan Providers")) {
                    cloudIntegration.refreshDetectedProviders()
                    cloudIntegration.scanAuthorizedRootsNow()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.primary)

                Spacer()

                if let lastScanAt = cloudIntegration.lastScanAt {
                    Text(String(
                        format: String(localized: "settings.watchdog.cloud.last_scan", defaultValue: "Last scan: %@"),
                        RelativeDateTimeFormatter().localizedString(for: lastScanAt, relativeTo: Date())
                    ))
                    .font(DesignSystem.Fonts.caption2())
                    .foregroundStyle(.secondary)
                }
            }
            .font(DesignSystem.Fonts.caption1(weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            SettingsInfoRow(
                text: String(
                    localized: "settings.watchdog.cloud.footer",
                    defaultValue: "Uses local sync folders + security-scoped access. Supports iCloud, Google Drive, OneDrive, Box, and other providers without OAuth APIs."
                )
            )
        }
    }

    private func cloudProviderRow(provider: CloudIntegrationService.Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: providerSymbol(for: provider.kind))
                    .foregroundStyle(provider.isAuthorized ? Color.green : Color.secondary)
                    .font(DesignSystem.Fonts.main(size: 14))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(DesignSystem.Fonts.body(weight: .medium))
                        .foregroundStyle(.primary)
                    Text(provider.rootPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(DesignSystem.Fonts.caption2())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(provider.statusText)
                    .font(DesignSystem.Fonts.caption2(weight: .bold))
                    .foregroundStyle(provider.needsRegrant ? Color.orange : (provider.isAuthorized ? Color.green : Color.secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 16) {
                Button(provider.needsRegrant
                    ? String(localized: "settings.watchdog.cloud.fix_access", defaultValue: "Fix Access")
                    : (provider.isAuthorized
                        ? String(localized: "settings.watchdog.cloud.regrant_access", defaultValue: "Regrant Access")
                        : String(localized: "settings.watchdog.cloud.grant_access", defaultValue: "Grant Access"))) {
                    grantCloudFolderAccess(for: provider)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.primary)

                if provider.isAuthorized {
                    Button(String(localized: "settings.watchdog.cloud.revoke", defaultValue: "Revoke")) {
                        cloudIntegration.revokeAuthorization(for: provider)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Colors.error)
                }

                Spacer()
            }
            .font(DesignSystem.Fonts.caption1(weight: .semibold))

            if let summary = cloudIntegration.scanSummary(for: provider) {
                Text(String(
                    format: String(localized: "settings.watchdog.cloud.indexed", defaultValue: "Indexed %1$d files • latest: %2$@"),
                    summary.fileCount,
                    summary.latestFileName ?? "—"
                ))
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(.secondary)
            }

            if let lastImport = cloudIntegration.lastImportDate(for: provider) {
                Text(String(
                    format: String(localized: "settings.watchdog.cloud.last_import", defaultValue: "Last import: %@"),
                    RelativeDateTimeFormatter().localizedString(for: lastImport, relativeTo: Date())
                ))
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(.secondary)
            }

            if provider.isAuthorized {
                let authorized = cloudIntegration.authorizedPaths(for: provider)
                if !authorized.isEmpty {
                    Text(String(
                        format: String(localized: "settings.watchdog.cloud.authorized", defaultValue: "Authorized: %@"),
                        authorized.joined(separator: ", ").replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    ))
                    .font(DesignSystem.Fonts.caption2())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Stale file monitor

    private var staleMonitorCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_stale_monitor"),
            icon: "clock.badge.exclamationmark",
            iconColor: DesignSystem.Colors.warning
        ) {
            SStepperRow(
                label: String(localized: "settings.watchdog.alert_threshold"),
                value: $thresholdDays,
                range: 1...30,
                valueLabel: { String(format: String(localized: "settings.watchdog.stepper_days"), $0) }
            )

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: String(localized: "settings.watchdog.scan_now"),
                actionLabel: String(localized: "settings.watchdog.run_scan"),
                actionColor: DesignSystem.Colors.info
            ) {
                Task { await staleMonitor.scanNow() }
            }

            if staleMonitor.staleFilesDetected > 0 {
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                SRow(
                    label: String(localized: "settings.watchdog.stale_detected_label"),
                    value: String(format: String(localized: "settings.watchdog.stale_detected"), staleMonitor.staleFilesDetected)
                )
            }
        }
    }

    // MARK: - Screenshot triage

    private var screenshotTriageCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_screenshot"),
            icon: "camera.viewfinder",
            iconColor: DesignSystem.Colors.primary
        ) {
            SToggleRow(
                label: String(localized: "settings.watchdog.auto_triage"),
                isOn: $screenshotTriage.isEnabled
            )

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SStepperRow(
                label: String(localized: "settings.watchdog.auto_delete"),
                value: $screenshotTriage.autoDeleteDays,
                range: 1...30,
                valueLabel: { String(format: String(localized: "settings.watchdog.stepper_days"), $0) }
            )

            if !screenshotTriage.pendingScreenshots.isEmpty {
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                SRow(
                    label: String(localized: "settings.watchdog.pending_screenshots"),
                    value: "\(screenshotTriage.pendingScreenshots.count)"
                )
            }
        }
    }

    // MARK: - Storage analytics

    private var storageAnalyticsCard: some View {
        SettingsCard(
            title: String(localized: "settings.watchdog.card_storage"),
            icon: "chart.pie.fill",
            iconColor: DesignSystem.Colors.info
        ) {
            SRow(
                label: String(localized: "settings.watchdog.total_vault"),
                value: analytics.formattedSize(analytics.totalVaultBytes)
            )

            if analytics.staleFileBytes > 0 {
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                SRow(
                    label: String(localized: "settings.watchdog.stale_files_label"),
                    value: analytics.formattedSize(analytics.staleFileBytes)
                )
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: String(localized: "settings.watchdog.refresh_analytics"),
                actionLabel: analytics.isRefreshing
                    ? String(localized: "settings.watchdog.refreshing")
                    : String(localized: "settings.watchdog.refresh"),
                actionColor: DesignSystem.Colors.info,
                isDisabled: analytics.isRefreshing
            ) {
                guard !analytics.isRefreshing else { return }
                Task { await analytics.refresh() }
            }
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
        panel.prompt = String(localized: "settings.watchdog.cloud.grant_access", defaultValue: "Grant Access")
        panel.message = String(
            format: String(localized: "settings.watchdog.cloud.grant_message", defaultValue: "Choose a folder inside %@ for College to scan and import."),
            provider.displayName
        )

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
