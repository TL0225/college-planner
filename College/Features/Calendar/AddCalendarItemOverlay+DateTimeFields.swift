// AddCalendarItemOverlay+DateTimeFields.swift
// Feature: Calendar
// Purpose: Date/time field components for AddCalendarItemOverlay (Phase 6 decomposition).

import CollegeCalendar
import SwiftUI

extension AddCalendarItemOverlay {
    struct FormattedDateField: View {
        @Binding var selection: Date
        let fontSize: CGFloat
        let textColor: Color

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd MMM yyyy"
            f.locale = .autoupdatingCurrent
            f.timeZone = .autoupdatingCurrent
            return f
        }()
        
        private var formattedDate: String {
            Self.formatter.string(from: selection)
        }
        
        var body: some View {
            Text(formattedDate)
                .font(DesignSystem.Fonts.main(size: fontSize))
                .foregroundStyle(textColor)
                .animation(.easeInOut(duration: 0.18), value: selection)
        }
    }

    struct MDYDateFields: View {
        @Binding var selection: Date
        let fontSize: CGFloat
        let textColor: Color

        @State private var monthText: String = ""
        @State private var dayText: String = ""
        @State private var yearText: String = ""
        @State private var isEditingAnyField: Bool = false

        var body: some View {
            HStack(spacing: 6) {
                numberField("MM", text: $monthText, maxDigits: 2)
                Text("/")
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.5))
                numberField("DD", text: $dayText, maxDigits: 2)
                Text("/")
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.5))
                numberField("YYYY", text: $yearText, maxDigits: 4, width: 56)
            }
            .onAppear { syncFromSelection() }
            .onChange(of: selection) { _, _ in
                if !isEditingAnyField {
                    syncFromSelection()
                }
            }
            .onChange(of: monthText) { _, _ in applyIfPossible() }
            .onChange(of: dayText) { _, _ in applyIfPossible() }
            .onChange(of: yearText) { _, _ in applyIfPossible() }
        }

        private func numberField(_ placeholder: String, text: Binding<String>, maxDigits: Int, width: CGFloat = 34) -> some View {
            TextField(
                placeholder,
                text: Binding(
                    get: { text.wrappedValue },
                    set: { newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        text.wrappedValue = String(digitsOnly.prefix(maxDigits))
                    }
                ),
                onEditingChanged: { editing in
                    isEditingAnyField = editing
                    if !editing {
                        applyIfPossible(force: true)
                    }
                }
            )
            .textFieldStyle(PlainTextFieldStyle())
            .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
            .foregroundStyle(textColor)
            .frame(width: width)
            .multilineTextAlignment(.center)
        }

        private func syncFromSelection() {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: selection)
            monthText = String(format: "%02d", comps.month ?? 1)
            dayText = String(format: "%02d", comps.day ?? 1)
            yearText = String(comps.year ?? cal.component(.year, from: Date()))
        }

        private func applyIfPossible(force: Bool = false) {
            guard let mRaw = Int(monthText), let dRaw = Int(dayText), let yRaw = Int(yearText) else { return }
            if !force && yearText.count < 2 { return }
            let cal = Calendar.current
            let year = (yearText.count <= 2) ? (2000 + yRaw) : yRaw
            let month = max(1, min(12, mRaw))
            let time = cal.dateComponents([.hour, .minute, .second], from: selection)
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.hour = time.hour
            comps.minute = time.minute
            comps.second = time.second
            let day = max(1, dRaw)
            comps.day = day
            var built: Date? = cal.date(from: comps)
            if built == nil {
                var adjustedDay = day
                while adjustedDay > 28 && built == nil {
                    adjustedDay -= 1
                    comps.day = adjustedDay
                    built = cal.date(from: comps)
                }
            }
            if let updated = built, updated != selection {
                selection = updated
            }
        }
    }

    struct TimeMenuField: View {
        @Binding var selection: Date
        let isDisabled: Bool
        let fontSize: CGFloat
        let textColor: Color
        let showsDurationFrom: Date?
        let onSelect: (Date) -> Void

        @State private var typedTimeText: String = ""
        @State private var typedTimeError: String?

        private var displayText: String {
            selection.formatted(date: .omitted, time: .shortened)
        }

        var body: some View {
            Menu {
                ForEach(TimeMenuField.timeOptions15Minutes, id: \.self) { option in
                    Button {
                        let calendar = Calendar.current
                        let updated = calendar.date(bySettingHour: option.hour ?? 0, minute: option.minute ?? 0, second: 0, of: selection) ?? selection
                        onSelect(updated)
                    } label: {
                        if let base = showsDurationFrom {
                            let label = TimeMenuField.menuLabel(for: option, selectionDate: selection, durationBase: base)
                            Text(label)
                        } else {
                            let label = TimeMenuField.menuLabel(for: option, selectionDate: selection)
                            Text(label)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type time")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    TextField("HH:MM", text: $typedTimeText)
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .onSubmit(applyTypedTime)
                    if let typedTimeError {
                        Text(typedTimeError)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                    Button("Apply") { applyTypedTime() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Divider()
                DatePicker(
                    "Exact time",
                    selection: Binding(
                        get: { selection },
                        set: { onSelect($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            } label: {
                Text(displayText)
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .regular))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
            .accessibilityLabel("Event time")
            .accessibilityHint("Choose a preset time, type HH:MM, or pick an exact time.")
            .onAppear {
                typedTimeText = selection.formatted(date: .omitted, time: .shortened)
            }
            .onChange(of: selection) { _, newValue in
                typedTimeText = newValue.formatted(date: .omitted, time: .shortened)
                typedTimeError = nil
            }
        }

        private func applyTypedTime() {
            if let updated = CalendarTimeEntryParser.date(byApplying: typedTimeText, to: selection) {
                typedTimeError = nil
                onSelect(updated)
            } else {
                typedTimeError = "Use HH:MM between 00:00 and 23:59."
            }
        }

        private static let timeOptions15Minutes: [DateComponents] = {
            var out: [DateComponents] = []
            out.reserveCapacity(96)
            for hour in 0..<24 {
                for minute in stride(from: 0, to: 60, by: 15) {
                    var comps = DateComponents()
                    comps.hour = hour
                    comps.minute = minute
                    out.append(comps)
                }
            }
            return out
        }()

        private static func menuLabel(for option: DateComponents, selectionDate: Date, durationBase: Date? = nil) -> String {
            let calendar = Calendar.current
            let candidate = calendar.date(bySettingHour: option.hour ?? 0, minute: option.minute ?? 0, second: 0, of: selectionDate) ?? selectionDate
            let timeText = candidate.formatted(date: .omitted, time: .shortened)

            guard let durationBase else {
                return timeText
            }

            // If candidate is not after base, interpret it as next day for duration display.
            var effectiveCandidate = candidate
            if effectiveCandidate <= durationBase {
                effectiveCandidate = calendar.date(byAdding: .day, value: 1, to: effectiveCandidate) ?? effectiveCandidate
            }

            let seconds = max(0, effectiveCandidate.timeIntervalSince(durationBase))
            let durationText = formatDuration(seconds)
            return "\(timeText) (\(durationText))"
        }

        private static func formatDuration(_ seconds: TimeInterval) -> String {
            let totalMinutes = max(0, Int(seconds.rounded() / 60))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return String(format: "%d:%02dh", hours, minutes)
        }
    }
}
