import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var calendarManager = CalendarIntegrationManager()
    @State private var isLogsPresented: Bool = false

    @State private var email = "alex.m@example.com"
    @State private var password = "password123" // Placeholder
    
    @State private var language = "English (US)"
    @State private var timeZone = "GMT-7"
    @State private var dateFormat = "MM/DD/YYYY"
    
    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @State private var density = "Compact"
    
    @State private var desktopAlerts = true
    @State private var emailDigest = false
    
    @State private var startWeekOn = "Sunday"
    @State private var defaultDuration = "30 min"
    @State private var showWeekends = true
    @State private var showDeclined = false
    
    // API Configuration Persistence
    // Removed user-overridable configuration variables.
    // Using hardcoded Info.plist values now.
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(DesignSystem.Fonts.main(size: 32, weight: .bold)) // Large Title
                        .foregroundColor(DesignSystem.Colors.textMain)
                    
                    Text("Refined configuration & preferences.")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                // Account Section
                SettingsSection(title: "ACCOUNT") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Email", value: email)
                        Divider()
                            .overlay(Color(nsColor: .separatorColor))
                        SettingsActionRow(label: "Password", actionText: "UPDATE") {
                            // Update password action
                        }
                    }
                    .background(DesignSystem.Colors.surface) // Group background
                    .cornerRadius(8)
                }
                
                // General Section
                SettingsSection(title: "GENERAL") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Language", value: language)
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsRow(label: "Time Zone", value: timeZone)
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsRow(label: "Date Format", value: dateFormat)
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                
                // Appearance Section
                SettingsSection(title: "APPEARANCE") {
                    VStack(spacing: 0) {
                        appearancePickerRow
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsRow(label: "Density", value: density)
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                
                // Notifications Section
                SettingsSection(title: "NOTIFICATIONS") {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            label: "Desktop Alerts",
                            subtitle: "Push notifications for events",
                            isOn: $desktopAlerts
                        )
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsToggleRow(
                            label: "Email Digest",
                            subtitle: "Daily summary at 8:00 AM",
                            isOn: $emailDigest
                        )
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                
                // Connected Apps Section
                SettingsSection(title: "CONNECTED APPS") {
                    VStack(spacing: 0) {
                        ConnectedAppRow(
                            icon: "calendar",
                            color: Color.blue,
                            name: "Google Calendar",
                            status: calendarManager.googleStatus.rawValue,
                            isSynced: calendarManager.googleStatus == .connected,
                            resyncAction: {
                                calendarManager.resyncGoogleNow()
                            },
                            showLogAction: {
                                GoogleDebugLog.revealInFinder()
                            },
                            action: {
                                if calendarManager.googleStatus == .disconnected {
                                    calendarManager.connectGoogle()
                                } else if calendarManager.googleStatus == .connected {
                                    // Optional: Add disconnect confirmation here if desired
                                    calendarManager.disconnectGoogle()
                                }
                            }
                        )
                        Divider().overlay(Color(nsColor: .separatorColor))
                        ConnectedAppRow(
                            icon: "envelope.fill",
                            color: Color.blue,
                            name: "Outlook Calendar",
                            status: "CONNECT",
                            isSynced: false,
                            resyncAction: {
                                // Not implemented yet.
                            }
                        )
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                
                // Calendar Section
                SettingsSection(title: "CALENDAR") {
                    VStack(spacing: 0) {
                        SettingsRow(label: "Start week on", value: startWeekOn)
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsRow(label: "Default duration", value: defaultDuration)
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsToggleRow(label: "Show weekends", subtitle: nil, isOn: $showWeekends)
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsToggleRow(label: "Show declined", subtitle: nil, isOn: $showDeclined)
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }

                // Diagnostics Section
                SettingsSection(title: "DIAGNOSTICS") {
                    VStack(spacing: 0) {
                        SettingsActionRow(label: "Logs", actionText: "OPEN") {
                            isLogsPresented = true
                        }
                        Divider().overlay(Color(nsColor: .separatorColor))
                        SettingsActionRow(label: "Console Capture", actionText: "ENABLE") {
                            // Ensure stdout/stderr are captured into console.log.
                            AppLogger.shared.redirectConsoleOutput()
                            DebugLogger.shared.log("Enabled console capture (stdout/stderr -> console.log)", category: .system, level: .info)
                        }
                    }
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                

                // API Configuration Section
                // Removed section for hardcoding test

            }
            .padding(.horizontal, 60) // Wide padding as shown in screenshot
            .padding(.bottom, 60)
        }
        .background(DesignSystem.Colors.bgMain) // Main page background
        .sheet(isPresented: $isLogsPresented) {
            AppLogsView()
        }
    }

    private var appearancePickerRow: some View {
        HStack {
            Text("Appearance")
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)

            Spacer()

            Picker("", selection: $appAppearanceRaw) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(16)
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .kerning(1.2) // Spacing for uppercase
            
            content
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            
            Spacer()
            
            Text(value)
                .font(DesignSystem.Fonts.main(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .padding(16)
    }
}

struct SettingsActionRow: View {
    let label: String
    let actionText: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            
            Spacer()
            
            Button(action: action) {
                Text(actionText)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary) // Cyan/Teal color
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

struct SettingsToggleRow: View {
    let label: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
                .scaleEffect(0.8) // Make toggle smaller like in screenshot
        }
        .padding(16)
    }
}

struct ConnectedAppRow: View {
    let icon: String // System name
    let color: Color
    let name: String
    let status: String
    let isSynced: Bool
    var resyncAction: (() -> Void)? = nil
    var showLogAction: (() -> Void)? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(name)
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
                .padding(.leading, 8)
            
            Spacer()

            if resyncAction != nil {
                Button(action: { resyncAction?() }) {
                    Text("Re-sync")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isSynced)
                .opacity(isSynced ? 1.0 : 0.4)
            }

            if showLogAction != nil {
                Button(action: { showLogAction?() }) {
                    Text("Show Log")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { action?() }) {
                if isSynced {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(status)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                } else {
                    Text(status)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}
