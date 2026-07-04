// SettingsCareerPanel.swift
// Feature: Settings
// Purpose: Settings module — SettingsCareerPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

struct SettingsCareerPanel: View {
    @AppStorage("career.board.keyboardNavigation") private var keyboardNavigation = true
    @AppStorage("career.board.quickAddEnabled") private var quickAddEnabled = true
    @AppStorage(CareerBoardLayout.storageKey) private var boardLayoutRaw: String = CareerBoardLayout.kanban.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(
                title: String(localized: "settings.career.board", defaultValue: "Board"),
                icon: "rectangle.split.3x1",
                iconColor: DesignSystem.Colors.primary
            ) {
                SPickerRow(
                    label: String(localized: "settings.career.default_layout", defaultValue: "Default board layout"),
                    selection: $boardLayoutRaw,
                    options: CareerBoardLayout.allCases.map(\.rawValue),
                    optionLabel: { CareerBoardLayout(rawValue: $0)?.displayName ?? $0 }
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SToggleRow(
                    label: String(localized: "settings.career.keyboard_nav", defaultValue: "Keyboard navigation"),
                    subtitle: String(
                        localized: "settings.career.keyboard_nav.help",
                        defaultValue: "Move between lanes and cards with the arrow keys."
                    ),
                    isOn: $keyboardNavigation
                )

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SToggleRow(
                    label: String(localized: "settings.career.quick_add", defaultValue: "Quick add"),
                    subtitle: String(
                        localized: "settings.career.quick_add.help",
                        defaultValue: "Add roles directly in the Interested lane."
                    ),
                    isOn: $quickAddEnabled
                )
            }

            SettingsJobBoardsPanel()
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }
}
