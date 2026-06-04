// SettingsChromeViews.swift
// Feature: Settings
// Purpose: Settings module — SettingsSidebarSearchField.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

struct SettingsSidebarSearchField: View {
    @Binding var text: String
    var prompt: String = String(localized: "settings.search.prompt", defaultValue: "Search settings")

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        }
    }
}

struct SettingsSearchSuggestionRow: View {
    let hit: SettingsSearchIndex.Hit
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(hit.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SettingsSidebarProfileStrip: View {
    let displayName: String
    let subtitle: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text(initials)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(profileBackground)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var profileBackground: Color {
        if isSelected { return Color.accentColor }
        if isHovered { return Color.primary.opacity(0.07) }
        return .clear
    }

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
}

struct SettingsGlassSidebarRow: View {
    let section: SettingsNavSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        section.badgeTint.gradient,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowFill: Color {
        if isSelected { return DesignSystem.Colors.sidebarSelection }
        if isHovered { return DesignSystem.Colors.sidebarHoverFill }
        return .clear
    }
}

private extension SettingsNavSection {
    var badgeTint: Color {
        switch self {
        case .profile: return .blue
        case .academics: return .teal
        case .calendar: return .red
        case .career: return .indigo
        case .assistant: return .purple
        case .documents: return .indigo
        case .brightspace: return .cyan
        case .shortcuts: return .orange
        case .app: return .gray
        case .privacyAndData: return .blue
        }
    }
}
