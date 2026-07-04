// CalendarInspectorOnboarding.swift
// Feature: Calendar
// Purpose: First-run tips when opening the event editor in inspector mode.

import SwiftUI

public enum CalendarInspectorOnboarding {
    public static let hasSeenTipsKey = "calendar.inspector.hasSeenOnboardingTips"

    public static var shouldShowTips: Bool {
        !UserDefaults.standard.bool(forKey: hasSeenTipsKey)
    }

    public static func markTipsSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenTipsKey)
    }

    /// Stable labels for inspector control groups (used by UI and contract tests).
    public static func inspectorControlTipTitles() -> [String] {
        [
            "Event time and recurrence",
            "Event location",
            "Course assignment",
            "Event details",
        ]
    }
}

public struct CalendarInspectorOnboardingTipsBanner: View {
    let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Inspector tips")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    Text("Use the cards below to edit time, location, course, and export settings. Save with the checkmark in the header.")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss inspector tips")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.yellow.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inspector tips. Use the cards below to edit time, location, course, and export settings.")
    }
}
