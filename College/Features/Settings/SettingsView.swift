// SettingsView.swift
// Feature: Settings
// Purpose: Settings module — SettingsView.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI
import AppKit
import WebKit

enum SettingsFeaturePreloadRegistration {
    @MainActor
    private static let preloadUserDefaultsKeys: [String] = [
        "appAppearance",
        "ui.inactiveStateEnabled",
        CalendarTimeZonePreference.storageKey,
        "onboarding.completed.v1",
        "calendar.timezone",
        "calendar.startWeekOn",
        "security.encryptionEnabled",
        LMSStorageKeys.lastVisitedURL,
        LMSStorageKeys.pendingLoadPortalOnNextAppear,
    ]

    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "settings",
                title: "Settings state",
                criticality: .bestEffort,
                timeoutSeconds: 0.6,
                retryLimit: 0,
                run: { _, onProgress, _ in
                    let defaults = UserDefaults.standard
                    for key in preloadUserDefaultsKeys {
                        _ = defaults.object(forKey: key)
                    }
                    onProgress(1)
                }
            )
        )
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    /// When set (standalone Settings window), drives section selection and window toolbar chrome.
    var session: SettingsSessionController? = nil

    private var collegePersistence: CollegePersistence { container.persistence }
    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @State private var localSelectedSection: SettingsNavSection = .profile
    @State private var sidebarSearchText: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var profile: Profile? { ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) }

    private var selectedSection: SettingsNavSection {
        session?.selectedSection ?? localSelectedSection
    }

    private var trimmedSearch: String {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSections: [SettingsNavSection] {
        if trimmedSearch.isEmpty {
            return SettingsNavSection.allCases
        }
        let fromIndex = SettingsSearchIndex.visibleSections(forSearchText: trimmedSearch)
        if !fromIndex.isEmpty { return fromIndex }
        return SettingsNavSection.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || $0.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var navigableSections: [SettingsNavSection] {
        visibleSections.filter { $0 != .profile }
    }

    private var searchHits: [SettingsSearchIndex.Hit] {
        guard !trimmedSearch.isEmpty else { return [] }
        return SettingsSearchIndex.suggestionHits(matching: trimmedSearch)
    }

    private var profileDisplayName: String {
        profile?.navBarDisplayLabel ?? ProfileShellSnapshot.welcomePlaceholder
    }

    private var profileSubtitle: String {
        let college = profile?.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return college.isEmpty ? String(localized: "settings.account.subtitle", defaultValue: "Student account") : college
    }

    var body: some View {
        NavigationSplitView(columnVisibility: navigationColumnVisibility) {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: SettingsMetrics.sidebarWidth)
        } detail: {
            settingsDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.settingsNavigateToSection, selectSection)
        .toolbar { historyToolbarContent }
        .onChange(of: session?.selectedSection) { _, newValue in
            guard let newValue else { return }
            localSelectedSection = newValue
        }
    }

    /// Back/forward history controls. The sidebar toggle is provided automatically by
    /// `NavigationSplitView` — we intentionally do not add a custom sidebar button here.
    @ToolbarContentBuilder
    private var historyToolbarContent: some ToolbarContent {
        if let session {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    session.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help(String(localized: "settings.history.back", defaultValue: "Back"))
                .disabled(!session.canGoBack)

                Button {
                    session.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help(String(localized: "settings.history.forward", defaultValue: "Forward"))
                .disabled(!session.canGoForward)
            }
        }
    }

    private var navigationColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                if let session {
                    return session.isSidebarVisible ? .all : .detailOnly
                }
                return columnVisibility
            },
            set: { newValue in
                if let session {
                    let isVisible = (newValue != .detailOnly)
                    Task { @MainActor in
                        session.isSidebarVisible = isVisible
                    }
                } else {
                    columnVisibility = newValue
                }
            }
        )
    }

    private var selectedSectionBinding: Binding<SettingsNavSection> {
        Binding(
            get: { selectedSection },
            set: { section in
                if let session {
                    Task { @MainActor in
                        session.selectSection(section)
                    }
                } else {
                    localSelectedSection = section
                }
            }
        )
    }

    private func selectSection(_ section: SettingsNavSection) {
        if let session {
            session.selectSection(section)
        } else {
            localSelectedSection = section
        }
    }

    private var settingsSidebar: some View {
        List(selection: selectedSectionBinding) {
            if trimmedSearch.isEmpty {
                Section {
                    SettingsSidebarProfileRow(
                        displayName: profileDisplayName,
                        subtitle: profileSubtitle
                    )
                    .tag(SettingsNavSection.profile)
                    .accessibilityIdentifier(SettingsNavSection.profile.accessibilityIdentifier)
                }

                Section {
                    ForEach(navigableSections, id: \.self) { section in
                        Label(section.displayName, systemImage: section.icon)
                            .symbolRenderingMode(.monochrome)
                            .tag(section)
                            .accessibilityIdentifier(section.accessibilityIdentifier)
                    }
                }
            } else {
                searchResultsContent
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $sidebarSearchText,
            prompt: String(localized: "settings.search.prompt", defaultValue: "Search settings")
        )
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchHits.isEmpty {
            Section {
                Text(String(localized: "settings.search.no_results", defaultValue: "No results"))
                    .font(DesignSystem.Fonts.body())
                    .foregroundStyle(.secondary)
            }
        } else {
            Section(String(localized: "settings.search.results", defaultValue: "Results")) {
                ForEach(searchHits) { hit in
                    Button {
                        selectSection(hit.section)
                        sidebarSearchText = ""
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hit.section.icon)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.title)
                                    .font(DesignSystem.Fonts.body(weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(hit.subtitle)
                                    .font(DesignSystem.Fonts.caption1())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.search.result")
                }
            }
        }
    }

    private var settingsDetailColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            settingsDetail(for: selectedSection)
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.vertical, DesignSystem.Spacing.lg)
                .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .navigationTitle(selectedSection.displayName)
    }

    @ViewBuilder
    private func settingsDetail(for section: SettingsNavSection) -> some View {
        switch section {
        case .profile:
            SettingsProfilePanel(activePage: $activePage)
        case .academics:
            SettingsAcademicsPanel()
        case .calendar:
            SettingsCalendarPanel()
        case .career:
            SettingsCareerPanel()
        case .assistant:
            SettingsAssistantPanel()
        case .documents:
            WatchdogSettingsPanel()
        case .lms:
            SettingsLMSPanel()
        case .shortcuts:
            SettingsWebShortcutsPanel()
        case .app:
            SettingsAppPanel()
        case .privacyAndData:
            SettingsPrivacyPanel()
        }
    }
}

// MARK: - SettingsLMSPanel

struct SettingsLMSPanel: View {

    // Legacy global portal-URL key retained for backward compatibility (see LMSPortalConfiguration).
    @AppStorage("brightspace.portalURL") private var portalURL: String = ""
    @AppStorage(LMSStorageKeys.savePassword) private var savePassword: Bool = true
    @State private var draftURL: String = ""
    @State private var clearSessionAlert: Bool = false
    @State private var sessionCleared: Bool = false
    @State private var connectionStatus: String = ""
    @State private var signedInHost: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            SettingsCard(
                title: String(localized: "settings.lms.portal_session", defaultValue: "Portal & Session"),
                icon: "globe",
                iconColor: DesignSystem.Colors.info
            ) {
                STextFieldRow(
                    label: String(localized: "settings.lms.portal_url", defaultValue: "Portal URL"),
                    subtitle: String(
                        localized: "settings.lms.portal_url.help",
                        defaultValue: "Your school's LMS sign-in URL."
                    ),
                    placeholder: LMSProvider.brightspace.portalURLPlaceholder,
                    text: $draftURL,
                    onSubmit: { portalURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines) }
                )

                Divider().padding(.horizontal, 18)

                if !signedInHost.isEmpty {
                    SRow(
                        label: String(localized: "settings.lms.signed_in_host", defaultValue: "Signed-in host"),
                        value: signedInHost,
                        valueSelectable: true
                    )
                    Divider().padding(.horizontal, 18)
                }

                if !connectionStatus.isEmpty {
                    SRow(
                        label: String(localized: "settings.lms.connection_status", defaultValue: "Connection"),
                        value: connectionStatus,
                        valueSelectable: true
                    )
                    Divider().padding(.horizontal, 18)
                }

                SToggleRow(
                    label: String(localized: "settings.lms.save_password", defaultValue: "Offer to save password"),
                    subtitle: String(
                        localized: "settings.lms.save_password.help",
                        defaultValue: "Prompts to save your LMS credentials in the Keychain."
                    ),
                    isOn: $savePassword
                )

                Divider().padding(.horizontal, 18)

                SActionRow(
                    label: String(localized: "settings.lms.test_connection", defaultValue: "Test connection"),
                    subtitle: String(
                        localized: "settings.lms.test_connection.help",
                        defaultValue: "Validates the portal URL format."
                    ),
                    actionLabel: String(localized: "settings.lms.test_connection.action", defaultValue: "Test…"),
                    action: testConnection
                )

                Divider().padding(.horizontal, 18)

                SActionRow(
                    label: String(localized: "settings.lms.clear_session", defaultValue: "Clear session data"),
                    subtitle: String(
                        localized: "settings.lms.clear_session.help",
                        defaultValue: "Signs you out and removes cookies and cached data."
                    ),
                    actionLabel: sessionCleared
                        ? String(localized: "settings.lms.cleared", defaultValue: "Cleared")
                        : String(localized: "settings.lms.clear", defaultValue: "Clear"),
                    actionColor: sessionCleared ? .secondary : DesignSystem.Colors.error,
                    role: .destructive
                ) {
                    clearSessionAlert = true
                }
            }

            SAdvancedDisclosure(
                title: String(localized: "settings.advanced.title", defaultValue: "Advanced"),
                subtitle: String(
                    localized: "settings.advanced.subtitle",
                    defaultValue: "Developer and reset options."
                )
            ) {
                SActionRow(
                    label: String(localized: "settings.lms.reset_onboarding", defaultValue: "Reset onboarding"),
                    subtitle: String(
                        localized: "settings.lms.reset_onboarding.help",
                        defaultValue: "Show the first-run setup flow again on next launch."
                    ),
                    actionLabel: String(localized: "settings.lms.reset", defaultValue: "Reset"),
                    actionColor: DesignSystem.Colors.warning
                ) {
                    OnboardingPreferenceBridge.resetOnboardingState()
                }
            }

            Spacer()
        }
        .onAppear {
            draftURL = portalURL
            refreshSignedInHost()
        }
        .confirmationDialog(
            String(localized: "settings.lms.clear_session.confirm.title", defaultValue: "Clear LMS session?"),
            isPresented: $clearSessionAlert,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.lms.clear", defaultValue: "Clear"), role: .destructive) {
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) {
                    sessionCleared = true
                }
                if let host = URL(string: portalURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
                    LMSKeychainService.shared.delete(host: host)
                }
                signedInHost = ""
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "settings.lms.clear_session.confirm.message",
                defaultValue: "This will sign you out of your learning management system and delete stored cookies and credentials."
            ))
        }
    }

    private func testConnection() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            connectionStatus = String(localized: "settings.lms.connection.invalid", defaultValue: "Invalid URL")
            return
        }
        portalURL = trimmed
        connectionStatus = String(localized: "settings.lms.connection.ok", defaultValue: "URL looks valid")
        signedInHost = host
    }

    private func refreshSignedInHost() {
        if let host = URL(string: portalURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host, !host.isEmpty {
            signedInHost = host
        }
    }
}
