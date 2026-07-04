// OverviewCard.swift
// Feature: Overview
// Purpose: Overview module — OverviewCard.
// Data: CollegePersistence / repositories when applicable.

//
//  OverviewCard.swift
//  College
//
//  Shared scrollable card shell used by every widget that doesn't
//  need a fully custom background (all except Weather and Music).
//

import SwiftUI

/// A scrollable card shell with the standard Overview glass surface,
/// rounded corners, shadow and 1-pt border used by dashboard widgets.
///
/// Usage:
/// ```swift
/// OverviewCard {
///     Text("Card title").font(...)
///     // content…
/// }
/// ```
struct OverviewCard<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.glassCardBase.background(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 40, x: 0, y: 15)
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }
}

struct OverviewWidgetHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        systemImage: String,
        accentColor: Color,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 30, height: 30)
                .background(accentColor.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(DesignSystem.Fonts.main(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: DesignSystem.Spacing.sm)

            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension OverviewWidgetHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String, accentColor: Color) {
        self.init(title, systemImage: systemImage, accentColor: accentColor) {
            EmptyView()
        }
    }
}

struct OverviewWidgetEmptyState: View {
    let title: String
    let message: String?
    let systemImage: String
    let accentColor: Color

    init(title: String, message: String? = nil, systemImage: String, accentColor: Color = .secondary) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(DesignSystem.Fonts.main(size: 20, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 42, height: 42)
                .background(accentColor.opacity(0.10))
                .clipShape(Circle())

            Text(title)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.lg)
    }
}

struct OverviewWidgetRowSurface<Content: View>: View {
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    init(accentColor: Color = .accentColor, @ViewBuilder content: @escaping () -> Content) {
        self.accentColor = accentColor
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.14), lineWidth: 1)
            )
    }
}

struct OverviewWidgetBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

extension View {
    /// Standard VoiceOver + UI-test surface for Overview dashboard widgets.
    func overviewWidgetSurface(id: String, title: String) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityIdentifier("overview.widget.\(id)")
    }
}
