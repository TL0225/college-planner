// BrightspaceView.swift
// Feature: Brightspace
// Purpose: Brightspace module — BrightspaceView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import WebKit
import AppKit

// MARK: - BrightspaceView
// Full-window embedded browser tab for Brightspace LMS.

struct BrightspaceView: View {
    @Environment(AppContainer.self) private var container
    private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var coordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    /// True when this tab is the visible portal page (for DEBUG diagnostics and Handoff).
    var isTabVisible: Bool = true

        private var collegePersistence: CollegePersistence { container.persistence }
    @State private var profileShell: ProfileShellSnapshot = ProfileReadBridge.shellSnapshot()
        @State private var showImportSheet: Bool = false
    @State private var showSavePasswordSheet: Bool = false
    @State private var pendingCredentialHost: String = ""
    @State private var pendingCredentialUsername: String = ""
    @State private var pendingCredentialPassword: String = ""

    private var brightspaceToolbarInitials: String {
        profileShell.initials == "…" ? "" : profileShell.initials
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Browser Chrome (Moved to toolbar)
            // Progress bar and active indicators stay at top of view
            HStack(spacing: 10) {
                Spacer()

                // Import button — shows when items are available
                if !coordinator.pendingImportItems.isEmpty && coordinator.pageType != .login {
                    Button(action: { showImportSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                            Text(String(format: String(localized: "brightspace.import_count_format"), coordinator.pendingImportItems.count))
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4f46e5").opacity(0.12))
                        .foregroundColor(Color(hex: "4f46e5"))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                // Active download indicators
                ForEach(coordinator.activeDownloads) { dl in
                    DownloadProgressPill(download: dl)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, !coordinator.pendingImportItems.isEmpty || !coordinator.activeDownloads.isEmpty ? 8 : 0)
            .background(Color(NSColor.windowBackgroundColor))

            // MARK: Progress bar
            if coordinator.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color(hex: "4f46e5"))
                        .frame(width: geo.size.width * coordinator.estimatedProgress, height: 2)
                        .animation(.easeInOut(duration: 0.1), value: coordinator.estimatedProgress)
                }
                .frame(height: 2)
            }

            // MARK: Web view
            BrightspaceWebViewRepresentable(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.windowBackground)
        .onAppear {
            BrightspaceDownloadManager.sweepStaleBrightspaceDownloadFolders()
            if UserDefaults.standard.bool(forKey: BrightspaceWebCoordinator.pendingLoadPortalKey) {
                UserDefaults.standard.set(false, forKey: BrightspaceWebCoordinator.pendingLoadPortalKey)
                coordinator.loadPortalAndClearResumeBookmark()
            } else {
                coordinator.restoreIfNeeded()
            }
            #if DEBUG
            if isTabVisible {
                coordinator.debugLogBrightspaceFocusSnapshot()
            }
            #endif
        }
        .onChange(of: isTabVisible) { _, visible in
            guard visible else { return }
            #if DEBUG
            coordinator.debugLogBrightspaceFocusSnapshot()
            #endif
        }
        .userActivity("com.timothy.college.brightspace", isActive: isTabVisible) { activity in
            activity.title = coordinator.pageTitle
            activity.webpageURL = coordinator.currentURL
            activity.isEligibleForHandoff = true
        }
        .onAppear { refreshProfileShell() }
        .onChange(of: collegePersistence.profileRevision) { _, _ in refreshProfileShell() }
        .onChange(of: coordinator.offerSavePassword) { _, offer in
            guard let offer else { return }
            pendingCredentialHost     = offer.host
            pendingCredentialUsername = offer.username
            pendingCredentialPassword = ""
            showSavePasswordSheet     = true
        }
        .sheet(isPresented: $showImportSheet) {
            BrightspaceImportSheet(
                items: Binding(
                    get: { brightspaceCoordinator.pendingImportItems },
                    set: { brightspaceCoordinator.pendingImportItems = $0 }
                ),
                isPresented: $showImportSheet
            )
            .dismissOnOutsideClickForSheet()
        }
        .sheet(isPresented: $showSavePasswordSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "brightspace.save_password_title"))
                    .font(.headline)
                Text(String(format: String(localized: "brightspace.save_password_message_format"), pendingCredentialHost))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pendingCredentialUsername)
                    .font(.body.weight(.medium))
                    .accessibilityLabel(String(localized: "brightspace.save_password_username_a11y"))
                SecureField(String(localized: "common.password"), text: $pendingCredentialPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "common.password"))
                HStack {
                    Button(String(localized: "common.not_now"), role: .cancel) {
                        showSavePasswordSheet = false
                        coordinator.dismissSavePasswordOffer()
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(String(localized: "common.save")) {
                        BrightspaceKeychainService.shared.save(
                            username: pendingCredentialUsername,
                            password: pendingCredentialPassword,
                            host: pendingCredentialHost
                        )
                        showSavePasswordSheet = false
                        coordinator.dismissSavePasswordOffer()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingCredentialPassword.isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 320)
            .presentationBackground(.thinMaterial)
            .dismissOnOutsideClickForSheet()
        }
    }

    private func refreshProfileShell() {
        profileShell = ProfileReadBridge.shellSnapshot(collegePersistence: collegePersistence)
    }
}

enum BrightspaceFeaturePreloadRegistration {
    /// Brightspace is warmed in `LaunchPreloadCoordinator` `.brightspaceWarmup` when configured.
    /// Avoid duplicating WKWebView preload during `.featureWarmup`.
    @MainActor
    static func register() {}
}

// MARK: - NSViewRepresentable wrapper

struct BrightspaceWebViewRepresentable: NSViewRepresentable {
    let coordinator: BrightspaceWebCoordinator

    func makeNSView(context: Context) -> WKWebView {
        return coordinator.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op — the coordinator owns the web view lifetime.
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        // No-op — coordinator retains the web view.
    }
}

// MARK: - Download Progress Pill

private struct DownloadProgressPill: View {
    let download: BrightspaceDownload

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: download.state == .importingToVault ? "folder.badge.arrow.down" : "arrow.down.circle")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(download.filename.prefix(18))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .lineLimit(1)
                if download.state == .importingToVault {
                    Text(String(localized: "brightspace.download.saving_to_documents"))
                        .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if download.state == .importingToVault {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 16)
            } else {
                ProgressView(value: download.progress)
                    .frame(width: 44)
                    .progressViewStyle(.linear)
                    .tint(Color(hex: "4f46e5"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "4f46e5").opacity(0.08))
        .cornerRadius(7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(download.state == .importingToVault
            ? String(localized: "brightspace.download.saving_to_documents_a11y")
            : String(localized: "brightspace.download.downloading_a11y"))
    }
}
