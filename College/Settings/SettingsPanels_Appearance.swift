import SwiftUI
import AppKit

// MARK: - Appearance Panel

struct SettingsAppearancePanel: View {
    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("ui.density")      private var density: String = "Comfortable"
    @AppStorage("ui.reduceMotion") private var reduceMotion: Bool = false
    @AppStorage(AppActivityCoordinator.inactiveStateEnabledKey) private var inactiveStateEnabled: Bool = true
    @AppStorage("ui.fontSize")     private var fontSize: String = "Medium"

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ForEach(AppAppearance.allCases) { mode in
                        appearanceCard(for: mode)
                    }
                }
                .padding(.vertical, 6)

                LabeledContent(String(localized: "settings.appearance.density_title")) {
                    HStack(spacing: 4) {
                        ForEach(["Compact", "Comfortable"], id: \.self) { option in
                            let isActive = density == option
                            Button(action: { density = option }) {
                                Text(densityOptionLabel(option))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isActive ? Color.white : Color.secondary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Group {
                                            if isActive {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.secondary)
                                            } else {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: isActive)
                        }
                    }
                }
            } header: {
                Label(
                    String(localized: "settings.appearance.card_appearance"),
                    systemImage: "paintpalette"
                )
            }

            Section {
                Toggle(String(localized: "settings.appearance.reduce_motion"), isOn: $reduceMotion)

                Toggle(
                    String(
                        localized: "settings.appearance.inactive_state",
                        defaultValue: "Reduce visual noise when inactive"
                    ),
                    isOn: $inactiveStateEnabled
                )
                .help("When enabled, the app subtly dims and defers periodic UI refresh while unfocused.")

                Picker(String(localized: "settings.appearance.font_size_label"), selection: $fontSize) {
                    ForEach(["Small", "Medium", "Large"], id: \.self) { opt in
                        Text(fontSizeLabel(opt)).tag(opt)
                    }
                }
            } header: {
                Label(
                    String(localized: "settings.appearance.card_system"),
                    systemImage: "macwindow"
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            AppActivityCoordinator.shared.refreshPolicyFromSettings()
        }
        .onChange(of: inactiveStateEnabled) { _, _ in
            AppActivityCoordinator.shared.refreshPolicyFromSettings()
        }
    }

    // MARK: - Appearance card builder

    @ViewBuilder
    private func appearanceCard(for mode: AppAppearance) -> some View {
        let isSelected = selectedAppearance == mode

        VStack(spacing: 8) {
            miniIllustration(for: mode)
                .frame(width: 160, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected
                                ? DesignSystem.Colors.primary
                                : Color(nsColor: .separatorColor).opacity(0.5),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(color: .black.opacity(isSelected ? 0.10 : 0), radius: 4, x: 0, y: 2)
                .animation(.easeInOut(duration: 0.15), value: isSelected)

            VStack(spacing: 2) {
                Text(modeTitle(for: mode))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primary : Color.primary)
                Text(modeSubtitle(for: mode))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
            }
        }
        .onTapGesture { appAppearanceRaw = mode.rawValue }
    }

    // MARK: - Mini illustrations

    @ViewBuilder
    private func miniIllustration(for mode: AppAppearance) -> some View {
        switch mode {
        case .light:  lightMiniPreview
        case .dark:   darkMiniPreview
        case .system: systemMiniPreview
        }
    }

    private var lightMiniPreview: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Color(hex: "e2e8f0")
                .frame(height: 14)
                .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Color(hex: "f1f5f9").frame(width: 36)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "cbd5e1")).frame(width: 70, height: 7)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "e2e8f0")).frame(width: 50, height: 7)
                Spacer().frame(height: 10)
                Circle().fill(Color(hex: "6366f1")).frame(width: 16, height: 16)
            }
            .padding(.leading, 48)
            .padding(.top, 22)
        }
    }

    private var darkMiniPreview: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: "111827")
            Color(hex: "1e293b")
                .frame(height: 14)
                .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Color(hex: "1e293b").frame(width: 36)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "475569")).frame(width: 70, height: 7)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "334155")).frame(width: 50, height: 7)
                Spacer().frame(height: 10)
                Circle().fill(Color(hex: "818cf8")).frame(width: 16, height: 16)
            }
            .padding(.leading, 48)
            .padding(.top, 22)
        }
    }

    private var systemMiniPreview: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.white
                Color(hex: "111827")
            }
            HStack(spacing: 0) {
                Color(hex: "e2e8f0").frame(maxWidth: .infinity)
                Color(hex: "1e293b").frame(maxWidth: .infinity)
            }
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Color(hex: "f1f5f9").frame(width: 36)
                Spacer()
            }
            Image(systemName: "sun.max")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "f59e0b"))
                .padding(.leading, 46)
                .padding(.top, 32)
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "818cf8"))
                .padding(.leading, 98)
                .padding(.top, 34)
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.6))
                    .frame(width: 1)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func densityOptionLabel(_ stored: String) -> String {
        switch stored {
        case "Compact":     return String(localized: "settings.appearance.density_compact")
        case "Comfortable": return String(localized: "settings.appearance.density_comfortable")
        default:            return stored
        }
    }

    private func fontSizeLabel(_ stored: String) -> String {
        switch stored {
        case "Small":  return String(localized: "settings.appearance.font_small")
        case "Medium": return String(localized: "settings.appearance.font_medium")
        case "Large":  return String(localized: "settings.appearance.font_large")
        default:       return stored
        }
    }

    private func modeTitle(for mode: AppAppearance) -> String {
        switch mode {
        case .system: return String(localized: "settings.appearance.card.system_title")
        case .light:  return String(localized: "settings.appearance.card.light_title")
        case .dark:   return String(localized: "settings.appearance.card.dark_title")
        }
    }

    private func modeSubtitle(for mode: AppAppearance) -> String {
        switch mode {
        case .system: return String(localized: "settings.appearance.card.system_subtitle")
        case .light:  return String(localized: "settings.appearance.card.light_subtitle")
        case .dark:   return String(localized: "settings.appearance.card.dark_subtitle")
        }
    }
}

// MARK: - Notifications Panel

struct SettingsNotificationsPanel: View {
    @AppStorage("notifications.desktopAlerts")  private var desktopAlerts: Bool = true
    @AppStorage("notifications.emailDigest")    private var emailDigest: Bool = false
    @AppStorage("notifications.eventReminders") private var eventReminders: Bool = true
    @AppStorage("notifications.assignmentDue")  private var assignmentDue: Bool = true
    @AppStorage("notifications.gradeUpdates")   private var gradeUpdates: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.notifications.desktop_alerts"), isOn: $desktopAlerts)
                Toggle(String(localized: "settings.notifications.email_digest"), isOn: $emailDigest)
                Toggle(String(localized: "settings.notifications.event_reminders"), isOn: $eventReminders)
                Toggle(String(localized: "settings.notifications.assignment_due"), isOn: $assignmentDue)
                Toggle(String(localized: "settings.notifications.grade_updates"), isOn: $gradeUpdates)
            } header: {
                Label(String(localized: "settings.notifications.card_title"), systemImage: "bell")
            }
        }
        .formStyle(.grouped)
    }
}
