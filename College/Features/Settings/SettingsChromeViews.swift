// SettingsChromeViews.swift
// Feature: Settings
// Purpose: Native sidebar profile row for Settings.

import SwiftUI

struct SettingsSidebarProfileRow: View {
    let displayName: String
    let subtitle: String

    private var initials: String {
        let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let a = parts[0].first.map(String.init) ?? ""
            let b = parts[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        if let f = displayName.first { return String(f).uppercased() }
        return "?"
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 36, height: 36)
                Text(initials)
                    .font(DesignSystem.Fonts.caption1(weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(DesignSystem.Fonts.body(weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(subtitle)")
    }
}
