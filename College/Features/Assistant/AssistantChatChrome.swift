// AssistantChatChrome.swift
// Feature: Assistant
// Purpose: Shared transcript column layout and bubble chrome (Ship C).

import SwiftUI

enum AssistantChatChrome {
    static let transcriptColumnMaxWidth: CGFloat = 760
    static let proseLineMaxWidth: CGFloat = 680
    static let bubbleCornerRadius: CGFloat = 12
    static let clusterSpacing: CGFloat = 12
    static let composerHorizontalPadding: CGFloat = 14

    static func userBubbleFill() -> Color {
        DesignSystem.Colors.accent.opacity(0.14)
    }

    static func userBubbleStroke() -> Color {
        DesignSystem.Colors.accent.opacity(0.25)
    }

    static func structuredCardFill() -> Color {
        DesignSystem.Colors.glassCardBase
    }

    static func structuredCardStroke() -> Color {
        DesignSystem.Colors.chromeStroke
    }
}
