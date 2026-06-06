// SettingsNavigation.swift
// Feature: Settings
// Purpose: Settings module — SettingsNavigateToSectionKey.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI

// MARK: - Section navigation (cross-links)

private struct SettingsNavigateToSectionKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: ((SettingsNavSection) -> Void)? = nil
}

extension EnvironmentValues {
    var settingsNavigateToSection: ((SettingsNavSection) -> Void)? {
        get { self[SettingsNavigateToSectionKey.self] }
        set { self[SettingsNavigateToSectionKey.self] = newValue }
    }
}

struct SettingsCrossLinkFooter: View {
    let message: String
    let buttonTitle: String
    let target: SettingsNavSection

    @Environment(\.settingsNavigateToSection) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(buttonTitle) {
                navigate?(target)
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

// MARK: - Label / action row

struct SettingsLabeledAction<Control: View>: View {
    let title: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        LabeledContent(title) {
            HStack {
                Spacer(minLength: 0)
                control()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

// MARK: - Shared time zone picker

struct SettingsTimeZonePicker: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            Button(String(localized: "settings.timezone.automatic", defaultValue: "Automatic (System)")) {
                selection = CalendarTimeZonePreference.systemValue
            }
            Divider()
            ForEach(CalendarTimeZonePreference.groupedOptions()) { group in
                Menu(group.region) {
                    ForEach(group.options) { option in
                        Button {
                            selection = option.id
                        } label: {
                            Text("\(option.title)  \(option.subtitle)")
                        }
                    }
                }
            }
        } label: {
            Text(selectionLabel)
        }
    }

    private var selectionLabel: String {
        guard selection != CalendarTimeZonePreference.systemValue else {
            return String(localized: "settings.timezone.automatic_short", defaultValue: "Automatic")
        }
        let parts = selection.split(separator: "/")
        if let last = parts.last {
            return String(last).replacingOccurrences(of: "_", with: " ")
        }
        return selection
    }
}
