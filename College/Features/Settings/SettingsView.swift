// SettingsView.swift
// Feature: Settings
// Purpose: Settings module — SettingsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import WebKit

enum SettingsFeaturePreloadRegistration {
    private static let preloadUserDefaultsKeys: [String] = [
        "appAppearance",
        "ui.inactiveStateEnabled",
        CalendarTimeZonePreference.storageKey,
        "onboarding.completed.v1",
        "calendar.timezone",
        "calendar.startWeekOn",
        "security.encryptionEnabled",
        "brightspace.lastVisitedURL",
        "brightspace.pendingLoadPortalOnNextAppear",
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
    @Binding var activePage: AppPage
    /// When set (standalone Settings window), drives section selection and window toolbar chrome.
    var session: SettingsSessionController? = nil

    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @EnvironmentObject private var collegePersistence: CollegePersistence
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

    private var searchSuggestions: [SettingsSearchIndex.Hit] {
        SettingsSearchIndex.suggestionHits(matching: trimmedSearch, limit: 8)
    }

    private var visibleSections: [SettingsNavSection] {
        if trimmedSearch.isEmpty {
            return SettingsNavSection.allCases
        }
        let fromIndex = SettingsSearchIndex.visibleSections(forSearchText: trimmedSearch)
        if !fromIndex.isEmpty { return fromIndex }
        return SettingsNavSection.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
        }
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
                .navigationSplitViewColumnWidth(
                    min: SettingsMetrics.sidebarWidth,
                    ideal: SettingsMetrics.sidebarWidth,
                    max: SettingsMetrics.sidebarWidth
                )
        } detail: {
            settingsDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .background(SettingsSidebarSplitLock(sidebarWidth: SettingsMetrics.sidebarWidth))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .environment(\.settingsNavigateToSection, selectSection)
        .onChange(of: session?.selectedSection) { _, newValue in
            guard let newValue else { return }
            localSelectedSection = newValue
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
                    session.isSidebarVisible = (newValue != .detailOnly)
                } else {
                    columnVisibility = newValue
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
        VStack(alignment: .leading, spacing: 10) {
            SettingsSidebarSearchField(text: $sidebarSearchText)

            if !trimmedSearch.isEmpty, !searchSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.search.suggestions", defaultValue: "Suggestions"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    ForEach(searchSuggestions) { hit in
                        SettingsSearchSuggestionRow(hit: hit) {
                            selectSection(hit.section)
                            sidebarSearchText = ""
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsSidebarProfileStrip(
                        displayName: profileDisplayName,
                        subtitle: profileSubtitle,
                        isSelected: selectedSection == .profile
                    ) {
                        selectSection(.profile)
                    }

                    ForEach(visibleSections, id: \.self) { section in
                        SettingsGlassSidebarRow(
                            section: section,
                            isSelected: selectedSection == section
                        ) {
                            selectSection(section)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private var settingsDetailColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            settingsDetail(for: selectedSection)
                .padding(32)
                .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .padding(.leading, 0)
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
                .environmentObject(calendarManager)
        case .career:
            SettingsCareerPanel()
        case .assistant:
            SettingsAssistantPanel()
        case .documents:
            WatchdogSettingsPanel()
        case .brightspace:
            SettingsBrightspacePanel()
        case .shortcuts:
            SettingsWebShortcutsPanel()
        case .app:
            SettingsAppPanel()
        case .privacyAndData:
            SettingsPrivacyPanel()
                .environmentObject(securityManager)
        }
    }
}

// MARK: - SettingsCard

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content

    init(
        title: String,
        icon: String,
        iconColor: Color = DesignSystem.Colors.primary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 0) {
                content
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
        }
        .padding(14)
        .background(DesignSystem.Colors.glassCardBase.background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }
}

// MARK: - SRow

struct SRow: View {
    let label: String
    var subtitle: String? = nil
    var value: String? = nil

    var body: some View {
        HStack(alignment: subtitle != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if let sub = subtitle {
                    Text(sub)
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            if let val = value {
                Text(val)
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }
}

// MARK: - SToggleRow

struct SToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: subtitle != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if let sub = subtitle {
                    Text(sub)
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }
}

// MARK: - SActionRow

struct SActionRow: View {
    let label: String
    var subtitle: String? = nil
    let actionLabel: String
    var actionColor: Color = DesignSystem.Colors.primary
    let action: () -> Void

    var body: some View {
        HStack(alignment: subtitle != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if let sub = subtitle {
                    Text(sub)
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            Button(action: action) {
                Text(actionLabel)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(actionColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }
}

// MARK: - SMenuRow

struct SMenuRow<SelectionType: Hashable>: View {
    let label: String
    var subtitle: String? = nil
    let currentDisplay: String
    let options: [SelectionType]
    let optionLabel: (SelectionType) -> String
    let onSelect: (SelectionType) -> Void

    var body: some View {
        HStack(alignment: subtitle != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if let sub = subtitle {
                    Text(sub)
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(optionLabel(option)) { onSelect(option) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentDisplay)
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
        .background(Color.primary.opacity(0.015))
    }
}

// MARK: - SettingsBrightspacePanel

private struct SettingsBrightspacePanel: View {

    @AppStorage("brightspace.portalURL") private var portalURL: String = ""
    @AppStorage("brightspace.savePassword") private var savePassword: Bool = true
    @State private var draftURL: String = ""
    @State private var clearSessionAlert: Bool = false
    @State private var sessionCleared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Portal & Session", icon: "network", iconColor: Color(hex: "0ea5e9")) {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Portal URL")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Text("Override the default URL (e.g. https://ublearns.buffalo.edu)")
                                .font(DesignSystem.Fonts.main(size: 11))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        Spacer()
                        TextField("https://brightspace.yourschool.edu", text: $draftURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .font(DesignSystem.Fonts.main(size: 12))
                            .onSubmit { portalURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    Divider().padding(.horizontal, 18)

                    SToggleRow(
                        label: "Offer to Save Password",
                        subtitle: "Prompts to save your Brightspace credentials in the Keychain",
                        isOn: $savePassword
                    )

                    Divider().padding(.horizontal, 18)

                    SActionRow(
                        label: "Clear Session Data",
                        subtitle: "Signs you out and removes cookies and cached data",
                        actionLabel: sessionCleared ? "Cleared" : "Clear",
                        actionColor: sessionCleared ? DesignSystem.Colors.textLight : DesignSystem.Colors.error
                    ) {
                        clearSessionAlert = true
                    }
                }
            }

            Spacer()
        }
        .onAppear { draftURL = portalURL }
        .alert("Clear Brightspace Session?", isPresented: $clearSessionAlert) {
            Button("Clear", role: .destructive) {
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) {
                    sessionCleared = true
                }
                if let host = URL(string: portalURL.isEmpty ? "https://ublearns.buffalo.edu" : portalURL)?.host {
                    BrightspaceKeychainService.shared.delete(host: host)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will sign you out of Brightspace and delete all stored cookies and credentials.")
        }
    }
}
