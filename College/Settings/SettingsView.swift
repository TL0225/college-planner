import SwiftUI
import AppKit
import WebKit

// MARK: - Nav Section Enum

enum SettingsNavSection: String, CaseIterable {
    case general       = "General"
    case account       = "Account"
    case appearance    = "Appearance"
    case notifications = "Notifications"
    case calendar      = "Calendar"
    case connectedApps = "Connected Apps"
    case brightspace   = "Brightspace"
    case webShortcuts  = "Web Shortcuts"
    case privacy       = "Privacy"
    case documents     = "Documents"

    var icon: String {
        switch self {
        case .general:       return "slider.horizontal.3"
        case .account:       return "person.circle"
        case .appearance:    return "paintpalette"
        case .notifications: return "bell"
        case .calendar:      return "calendar"
        case .connectedApps:  return "apps.iphone"
        case .brightspace:    return "network"
        case .webShortcuts:   return "link.circle"
        case .privacy:        return "lock.shield"
        case .documents:     return "folder.badge.gear"
        }
    }
}

enum SettingsFeaturePreloadRegistration {
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
                    _ = UserDefaults.standard.dictionaryRepresentation()
                    onProgress(1)
                }
            )
        )
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Binding var activePage: AppPage
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @State private var selectedSection: SettingsNavSection = .general
    @State private var sidebarSearchText: String = ""

    private var filteredSections: [SettingsNavSection] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsNavSection.allCases }
        return SettingsNavSection.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // LEFT RAIL
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                    .foregroundStyle(.primary)

                SettingsSidebarSearchField(text: $sidebarSearchText)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredSections, id: \.self) { section in
                            SettingsGlassSidebarRow(
                                section: section,
                                isSelected: selectedSection == section,
                                action: { selectedSection = section }
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                Button(action: { securityManager.lock() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                        Text("Sign Out")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .foregroundStyle(DesignSystem.Colors.error)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                Text("Version \(version)")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 254)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )

            // RIGHT CONTENT
            ZStack {
                ScrollView {
                    SettingsGeneralPanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .general ? 1 : 0)
                .allowsHitTesting(selectedSection == .general)

                ScrollView {
                    SettingsAccountPanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .account ? 1 : 0)
                .allowsHitTesting(selectedSection == .account)

                ScrollView {
                    SettingsAppearancePanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .appearance ? 1 : 0)
                .allowsHitTesting(selectedSection == .appearance)

                ScrollView {
                    SettingsNotificationsPanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .notifications ? 1 : 0)
                .allowsHitTesting(selectedSection == .notifications)

                ScrollView {
                    SettingsConnectedAppsPanel()
                        .environmentObject(calendarManager)
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .connectedApps ? 1 : 0)
                .allowsHitTesting(selectedSection == .connectedApps)

                ScrollView {
                    SettingsCalendarPanel()
                        .environmentObject(calendarManager)
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .calendar ? 1 : 0)
                .allowsHitTesting(selectedSection == .calendar)

                ScrollView {
                    SettingsBrightspacePanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .brightspace ? 1 : 0)
                .allowsHitTesting(selectedSection == .brightspace)

                ScrollView {
                    SettingsWebShortcutsPanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .webShortcuts ? 1 : 0)
                .allowsHitTesting(selectedSection == .webShortcuts)

                ScrollView {
                    SettingsPrivacyPanel()
                        .environmentObject(securityManager)
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .privacy ? 1 : 0)
                .allowsHitTesting(selectedSection == .privacy)

                ScrollView {
                    WatchdogSettingsPanel()
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .opacity(selectedSection == .documents ? 1 : 0)
                .allowsHitTesting(selectedSection == .documents)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 700)
        .background(DesignSystem.Colors.bgMain)
    }

}

// MARK: - Sidebar Nav Item

private struct SidebarNavItem: View {
    let label: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .font(DesignSystem.Fonts.main(size: 13, weight: isSelected ? .semibold : .regular))
        .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.primary.opacity(0.15))
                } else {
                    Color.clear
                }
            }
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
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
            Text("Brightspace")
                .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            SettingsCard(title: "Portal & Session", icon: "network", iconColor: Color(hex: "0ea5e9")) {
                VStack(spacing: 0) {
                    // Portal URL field
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

                    // Save password toggle
                    SToggleRow(
                        label: "Offer to Save Password",
                        subtitle: "Prompts to save your Brightspace credentials in the Keychain",
                        isOn: $savePassword
                    )

                    Divider().padding(.horizontal, 18)

                    // Clear session
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
                // Also remove saved credentials for the portal host
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
