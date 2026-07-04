// AcademicCalendarHubPickerSheet.swift
// Feature: Calendar
// Purpose: Pick a sub-calendar from an academic calendar hub page.

import SwiftUI

struct AcademicCalendarHubPickerSheet: View {
  let candidates: [AcademicCalendarSubCalendarCandidate]
  let suggestedURL: String?
  let neutralMode: Bool
  let onSelect: (AcademicCalendarSubCalendarCandidate) -> Void
  let onCancel: () -> Void

  @State private var selection: String = ""

  init(
    candidates: [AcademicCalendarSubCalendarCandidate],
    suggestedURL: String?,
    neutralMode: Bool = false,
    onSelect: @escaping (AcademicCalendarSubCalendarCandidate) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.candidates = candidates
    self.suggestedURL = suggestedURL
    self.neutralMode = neutralMode
    self.onSelect = onSelect
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(localized: "settings.calendar.term_dates_hub_title", defaultValue: "Choose Term Calendar"))
        .font(DesignSystem.Fonts.title3(weight: .semibold))
      Text(String(
        localized: "settings.calendar.term_dates_hub_subtitle",
        defaultValue: "This school lists multiple calendars. Pick the one that matches your program."
      ))
      .font(DesignSystem.Fonts.body())
      .foregroundStyle(.secondary)

      Picker("Sub-calendar", selection: $selection) {
        ForEach(candidates) { candidate in
          HStack {
            Text(candidate.label)
            if !neutralMode, candidate.url == suggestedURL {
              Text(String(localized: "settings.calendar.recommended", defaultValue: "Recommended"))
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
            }
          }
          .tag(candidate.url)
        }
      }
      .pickerStyle(.menu)

      HStack {
        Button("Cancel", action: onCancel)
        Spacer()
        Button("Continue") {
          if let candidate = candidates.first(where: { $0.url == selection }) {
            onSelect(candidate)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selection.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 480)
    .onAppear {
      if !neutralMode, let suggestedURL, candidates.contains(where: { $0.url == suggestedURL }) {
        selection = suggestedURL
      } else if let first = candidates.first {
        selection = first.url
      }
    }
  }
}

#Preview {
  AcademicCalendarHubPickerSheet(
    candidates: [
      AcademicCalendarSubCalendarCandidate(label: "Gabelli School of Business: Undergraduate", url: "https://example.com/ug"),
      AcademicCalendarSubCalendarCandidate(label: "School of Law", url: "https://example.com/law")
    ],
    suggestedURL: nil,
    onSelect: { _ in },
    onCancel: {}
  )
}
