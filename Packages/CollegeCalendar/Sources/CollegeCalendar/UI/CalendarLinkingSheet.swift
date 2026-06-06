// CalendarLinkingSheet.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarLinkingSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Shown after connecting Google/Apple/Outlook or subscribing to ICS.
struct CalendarLinkingSheet: View {
    let providerName: String
    let providerCalendars: [(id: String, name: String)]
    @Binding var configs: [CalendarLinkConfig]
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Choose how \(providerName) calendars appear in College.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(providerCalendars, id: \.id) { cal in
                Section(cal.name) {
                    Picker("Link mode", selection: binding(for: cal.id).mode) {
                        Text("Use provider name & color").tag(CalendarLinkConfig.Mode.mirrorProvider)
                        Text("Map to app calendar").tag(CalendarLinkConfig.Mode.mapToAppCalendar)
                    }
                    if binding(for: cal.id).mode.wrappedValue == .mapToAppCalendar {
                        TextField("App calendar ID (e.g. Apple:School)", text: binding(for: cal.id).appCalendarID)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    CalendarLinkConfig.saveAll(configs)
                    onDone()
                    dismiss()
                }
            }
        }
    }

    private func binding(for providerID: String) -> (
        mode: Binding<CalendarLinkConfig.Mode>,
        appCalendarID: Binding<String>
    ) {
        let index: Int = {
            if let existing = configs.firstIndex(where: { $0.providerCalendarID == providerID }) {
                return existing
            }
            let entry = CalendarLinkConfig(
                providerCalendarID: providerID,
                providerSource: providerName,
                mode: .mirrorProvider,
                appCalendarID: nil,
                displayName: nil,
                colorHex: nil
            )
            configs.append(entry)
            return configs.count - 1
        }()

        return (
            Binding(
                get: { configs[index].mode },
                set: { configs[index].mode = $0 }
            ),
            Binding(
                get: { configs[index].appCalendarID ?? "" },
                set: { configs[index].appCalendarID = $0.isEmpty ? nil : $0 }
            )
        )
    }
}
