// AssistantToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct AssistantToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher
    let assistantScene: AssistantSceneState

    private var projection: AssistantSceneState.ToolbarProjection {
        assistantScene.toolbarProjection
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Label(projection.activeBadgeText, systemImage: projection.roleSymbol)
                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .accessibilityIdentifier("assistant.sessionBadge")

            if let inferenceProviderLabel = projection.inferenceProviderLabel {
                Text(inferenceProviderLabel)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .accessibilityIdentifier("assistant.aiProviderBadge")
                    .accessibilityLabel("AI provider: \(inferenceProviderLabel)")
            }

            if let fallbackBanner = projection.inferenceFallbackBanner {
                Text(fallbackBanner)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .lineLimit(1)
                    .accessibilityIdentifier("assistant.fallbackBanner")
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                dispatcher.dispatch(.assistant(.openWebMemory))
            } label: {
                Label("Web Memory", systemImage: "books.vertical")
            }
            .help("Open saved web memory")
            .accessibilityIdentifier("toolbar.assistant.webMemory")

            Menu {
                Button {
                    dispatcher.dispatch(.assistant(.regenerateLastReply))
                } label: {
                    Label("Regenerate Last Reply", systemImage: "arrow.clockwise")
                }
                Button {
                    dispatcher.dispatch(.assistant(.exportTranscript))
                } label: {
                    Label("Export Transcript", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    dispatcher.dispatch(.assistant(.clearThread))
                } label: {
                    Label("Clear Thread", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Assistant actions")
            .accessibilityIdentifier("toolbar.assistant.more")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

enum AssistantToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        AssistantToolbarContent(
            dispatcher: context.dispatcher,
            assistantScene: context.assistantScene
        )
    }
}
