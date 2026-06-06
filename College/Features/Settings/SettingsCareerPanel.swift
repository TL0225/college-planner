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

    private var boardLayout: CareerBoardLayout {
        CareerBoardLayout(rawValue: boardLayoutRaw) ?? .kanban
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Form {
                Section(String(localized: "settings.career.board", defaultValue: "Board")) {
                    Picker(String(localized: "settings.career.default_layout", defaultValue: "Default board layout"), selection: $boardLayoutRaw) {
                        ForEach(CareerBoardLayout.allCases) { layout in
                            Text(layout.displayName).tag(layout.rawValue)
                        }
                    }
                    Toggle(String(localized: "settings.career.keyboard_nav", defaultValue: "Enable keyboard navigation"), isOn: $keyboardNavigation)
                    Toggle(String(localized: "settings.career.quick_add", defaultValue: "Enable quick add in Interested lane"), isOn: $quickAddEnabled)
                }
            }
            .formStyle(.grouped)

            SettingsJobBoardsPanel()
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
    }
}
