// LMSView.swift
// Feature: LMS
// Purpose: LMS module — LMSView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import WebKit
import AppKit

// MARK: - LMSView
// Full-window embedded browser tab for LMS LMS.

struct LMSView: View {
    @Environment(AppContainer.self) private var container
    private var lmsCoordinator: LMSWebCoordinator { container.lmsCoordinator }
    private var coordinator: LMSWebCoordinator { container.lmsCoordinator }
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    /// True when this tab is the visible portal page (for DEBUG diagnostics and Handoff).
    var isTabVisible: Bool = true

    private var collegePersistence: CollegePersistence { container.persistence }
    private var webPortalScene: WebPortalSceneState { container.webPortalScene }
    private var toolbarDispatcher: ToolbarDispatcher { container.toolbarDispatcher }
    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    @State private var profileShell: ProfileShellSnapshot = ProfileReadBridge.shellSnapshot()
        @State private var showImportSheet: Bool = false
    @State private var showSavePasswordSheet: Bool = false
    @State private var pendingCredentialHost: String = ""
    @State private var pendingCredentialUsername: String = ""
    @State private var pendingCredentialPassword: String = ""

    private var lmsToolbarInitials: String {
        profileShell.initials == "…" ? "" : profileShell.initials
    }

    var body: some View {
        Group {
            if coordinator.resolvePortalURL() == nil {
                ContentUnavailableView {
                    Label("Configure your portal URL", systemImage: "network.badge.shield.half.filled")
                } description: {
                    Text("Add your LMS portal URL in Settings before opening the learning management system.")
                } actions: {
                    Button("Open Settings") {
                        MacPreferencesWindow.show(section: .lms)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            Text(String(format: String(localized: "lms.import_count_format"), coordinator.pendingImportItems.count))
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "4f46e5").opacity(0.12))
                        .foregroundStyle(Color(hex: "4f46e5"))
                        .clipShape(.rect(cornerRadius: 8))
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
            LMSWebViewRepresentable(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.windowBackground)
        .onAppear {
            LMSDownloadManager.sweepStaleLMSDownloadFolders()
            wireToolbarIfVisible()
            syncToolbarChrome()
            if UserDefaults.standard.bool(forKey: LMSWebCoordinator.pendingLoadPortalKey) {
                UserDefaults.standard.set(false, forKey: LMSWebCoordinator.pendingLoadPortalKey)
                coordinator.loadPortalAndClearResumeBookmark()
            } else {
                coordinator.restoreIfNeeded()
            }
            #if DEBUG
            if isTabVisible {
                coordinator.debugLogLMSFocusSnapshot()
            }
            #endif
        }
        .onDisappear {
            if isTabVisible {
                toolbarHandlerToken?.invalidate()
                toolbarHandlerToken = nil
            }
        }
        .onChange(of: isTabVisible) { _, visible in
            if visible {
                wireToolbarIfVisible()
                syncToolbarChrome()
            } else {
                toolbarHandlerToken?.invalidate()
                toolbarHandlerToken = nil
            }
            guard visible else { return }
            #if DEBUG
            coordinator.debugLogLMSFocusSnapshot()
            #endif
        }
        .onChange(of: coordinator.canGoBack) { _, val in
            guard isTabVisible else { return }
            webPortalScene.canGoBack = val
        }
        .onChange(of: coordinator.canGoForward) { _, val in
            guard isTabVisible else { return }
            webPortalScene.canGoForward = val
        }
        .onChange(of: coordinator.isLoading) { _, val in
            guard isTabVisible else { return }
            webPortalScene.isLoading = val
        }
        .onChange(of: coordinator.pageTitle) { _, val in
            guard isTabVisible else { return }
            let trimmed = LMSWebCoordinator.sanitizedDocumentTitle(val)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            webPortalScene.title = trimmed.isEmpty
                ? String(localized: "app.page.lms")
                : trimmed
        }
        .userActivity("com.timothy.college.lms", isActive: isTabVisible) { activity in
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
            LMSImportSheet(
                items: Binding(
                    get: { lmsCoordinator.pendingImportItems },
                    set: { lmsCoordinator.pendingImportItems = $0 }
                ),
                isPresented: $showImportSheet
            )
            .dismissOnOutsideClickForSheet()
        }
        .sheet(isPresented: $showSavePasswordSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "lms.save_password_title"))
                    .font(.headline)
                Text(String(format: String(localized: "lms.save_password_message_format"), pendingCredentialHost))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pendingCredentialUsername)
                    .font(.body.weight(.medium))
                    .accessibilityLabel(String(localized: "lms.save_password_username_a11y"))
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
                        LMSKeychainService.shared.save(
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
            .padding(DesignSystem.Spacing.xl)
            .frame(minWidth: 320)
            .presentationBackground(.thinMaterial)
            .dismissOnOutsideClickForSheet()
        }
    }

    private func refreshProfileShell() {
        profileShell = ProfileReadBridge.shellSnapshot(collegePersistence: collegePersistence)
    }

    private func wireToolbarIfVisible() {
        guard isTabVisible else { return }
        webPortalScene.title = String(localized: "app.page.lms")
        syncToolbarChrome()

        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = toolbarDispatcher.register(owner: .webPortal(nil)) { action in
            guard case .web(let webAction) = action else { return }
            switch webAction {
            case .back:
                coordinator.goBack()
            case .forward:
                coordinator.goForward()
            case .reload:
                coordinator.reload()
            case .portalHome:
                coordinator.loadPortalHome()
            case .findInPage:
                coordinator.presentFindNavigator()
            }
        }
    }

    private func syncToolbarChrome() {
        webPortalScene.canGoBack = coordinator.canGoBack
        webPortalScene.canGoForward = coordinator.canGoForward
        webPortalScene.isLoading = coordinator.isLoading
        let trimmed = LMSWebCoordinator.sanitizedDocumentTitle(coordinator.pageTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            webPortalScene.title = trimmed
        }
    }
}

enum LMSFeaturePreloadRegistration {
    /// The LMS portal is warmed in `LaunchPreloadCoordinator` `.lmsWarmup` when configured.
    /// This descriptor only marks feature-warmup coverage; it must not duplicate the WKWebView preload.
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "lms",
                title: LMSPortalConfiguration.lmsDisplayName,
                criticality: .bestEffort,
                timeoutSeconds: 0.3,
                retryLimit: 0,
                run: { _, onProgress, _ in
                    onProgress(1)
                }
            )
        )
    }
}

// MARK: - NSViewRepresentable wrapper

struct LMSWebViewRepresentable: NSViewRepresentable {
    let coordinator: LMSWebCoordinator

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
    let download: LMSDownload

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: download.state == .importingToVault ? "folder.badge.arrow.down" : "arrow.down.circle")
                .font(DesignSystem.Fonts.main(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(download.filename.prefix(18))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .lineLimit(1)
                if download.state == .importingToVault {
                    Text(String(localized: "lms.download.saving_to_documents"))
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
        .clipShape(.rect(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(download.state == .importingToVault
            ? String(localized: "lms.download.saving_to_documents_a11y")
            : String(localized: "lms.download.downloading_a11y"))
    }
}
