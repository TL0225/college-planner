import SwiftUI

/// Unified card chrome for Overview, Settings, and feature surfaces.
public struct AppCard<Content: View>: View {
    private let title: String?
    private let icon: String?
    private let iconColor: Color?
    private let content: Content

    public init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if let title {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(iconColor ?? DesignSystem.Colors.primary)
                    }
                    Text(title)
                        .font(DesignSystem.Fonts.headline())
                        .foregroundStyle(DesignSystem.Colors.textMain)
                }
            }
            content
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        }
    }
}

public extension View {
    func cardSurface(padding: CGFloat = DesignSystem.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(DesignSystem.Colors.surface)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            }
    }
}
