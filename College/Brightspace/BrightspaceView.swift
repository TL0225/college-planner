import SwiftUI
import WebKit
import CoreData
#if os(macOS)
import AppKit
#endif

// MARK: - BrightspaceView
// Full-window embedded browser tab for Brightspace LMS.

struct BrightspaceView: View {
    @Binding var activePage: AppPage
    /// True when this tab is the visible portal page (for DEBUG diagnostics and Handoff).
    var isTabVisible: Bool = true

    @FetchRequest(fetchRequest: BrightspaceView.profileRequest)
    private var profileRows: FetchedResults<ProfileEntity>

    @EnvironmentObject private var coordinator: BrightspaceWebCoordinator
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    #if os(macOS)
    @EnvironmentObject private var toolbarCoordinator: AppToolbarCoordinator
    #endif

    @State private var showImportSheet: Bool = false
    @State private var showSavePasswordSheet: Bool = false
    @State private var pendingCredentialHost: String = ""
    @State private var pendingCredentialUsername: String = ""
    @State private var pendingCredentialPassword: String = ""

    private static var profileRequest: NSFetchRequest<ProfileEntity> {
        let r = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
        r.fetchLimit = 1
        r.sortDescriptors = []
        return r
    }

    private var brightspaceToolbarInitials: String {
        Self.initialsFromProfileName(profileRows.first?.name)
    }

    private static func initialsFromProfileName(_ raw: String?) -> String {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "" }
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2,
           let a = parts[0].first,
           let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
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
            #if os(macOS)
            syncBrightspaceToolbarState()
            toolbarCoordinator.onBsBack    = { [self] in coordinator.goBack() }
            toolbarCoordinator.onBsForward = { [self] in coordinator.goForward() }
            toolbarCoordinator.onBsReload  = { [self] in coordinator.reload() }
            toolbarCoordinator.onBsPortalHome = { [self] in coordinator.loadPortalHome() }
            toolbarCoordinator.onBsFind    = { [self] in coordinator.presentFindNavigator() }
            toolbarCoordinator.profileInitials = brightspaceToolbarInitials
            #endif
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
        #if os(macOS)
        .onChange(of: coordinator.canGoBack)    { _, val in toolbarCoordinator.bsCanGoBack   = val }
        .onChange(of: coordinator.canGoForward) { _, val in toolbarCoordinator.bsCanGoForward = val }
        .onChange(of: coordinator.isLoading)    { _, val in toolbarCoordinator.bsIsLoading    = val }
        .onChange(of: brightspaceToolbarInitials) { _, val in toolbarCoordinator.profileInitials = val }
        #endif
        .onChange(of: coordinator.offerSavePassword) { _, offer in
            guard let offer else { return }
            pendingCredentialHost     = offer.host
            pendingCredentialUsername = offer.username
            pendingCredentialPassword = ""
            showSavePasswordSheet     = true
        }
        .sheet(isPresented: $showImportSheet) {
            BrightspaceImportSheet(
                items: $coordinator.pendingImportItems,
                isPresented: $showImportSheet
            )
            .environmentObject(coreDataManager)
            .environmentObject(appNotifications)
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

    #if os(macOS)
    private func syncBrightspaceToolbarState() {
        toolbarCoordinator.bsCanGoBack    = coordinator.canGoBack
        toolbarCoordinator.bsCanGoForward = coordinator.canGoForward
        toolbarCoordinator.bsIsLoading    = coordinator.isLoading
    }
    #endif
}

enum BrightspaceFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "brightspace",
                title: "Brightspace refresh",
                criticality: .bestEffort,
                timeoutSeconds: 2.2,
                retryLimit: 0,
                run: { context, onProgress, onDetail in
                    try await context.brightspaceCoordinator.preloadPortalForLaunch(
                        progress: { onProgress($0) },
                        detail: { onDetail($0) }
                    )
                    onProgress(1)
                }
            )
        )
    }
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
