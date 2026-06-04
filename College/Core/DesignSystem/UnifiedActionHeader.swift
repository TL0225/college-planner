// UnifiedActionHeader.swift
// Feature: Core
// Purpose: Core module — UnifiedActionHeader.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Shared end-to-end header with fixed top-right SF Symbol actions.
/// Keeps title/subtitle and optional accessory content on the left,
/// while plus/sidebar icons stay pinned in a consistent location.
struct UnifiedActionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil

    var titleFont: Font = .system(size: 22, weight: .bold)
    var subtitleFont: Font = .system(size: 15, weight: .semibold)
    var titleColor: Color = .primary
    var subtitleColor: Color = .secondary

    var topPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 24
    var bottomPadding: CGFloat = 16
    var titleToContentSpacing: CGFloat = 4

    var plusAction: (() -> Void)? = nil
    var plusHelp: String = "Add"
    var plusDisabled: Bool = false

    var sidebarAction: (() -> Void)? = nil
    var sidebarHelp: String = "Toggle Inspector"
    var sidebarBounceValue: Bool = false
    var sidebarShortcut: KeyboardShortcut? = nil

    @ViewBuilder var accessory: () -> Accessory

    private var actionCount: Int {
        (plusAction == nil ? 0 : 1) + (sidebarAction == nil ? 0 : 1)
    }

    private var titleTrailingInset: CGFloat {
        switch actionCount {
        case 2: return 80
        case 1: return 44
        default: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: titleToContentSpacing) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .padding(.trailing, titleTrailingInset)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
            }

            accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if let plusAction {
                    Button(action: plusAction) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(plusHelp)
                    .disabled(plusDisabled)
                }

                if let sidebarAction {
                    Group {
                        if let sidebarShortcut {
                            Button(action: sidebarAction) {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .symbolEffect(.bounce, value: sidebarBounceValue)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                            }
                            .keyboardShortcut(sidebarShortcut)
                        } else {
                            Button(action: sidebarAction) {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .symbolEffect(.bounce, value: sidebarBounceValue)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(sidebarHelp)
                }
            }
            .frame(height: 20)
        }
        .padding(.top, topPadding)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
    }
}

extension UnifiedActionHeader where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        titleFont: Font = .system(size: 22, weight: .bold),
        subtitleFont: Font = .system(size: 15, weight: .semibold),
        titleColor: Color = .primary,
        subtitleColor: Color = .secondary,
        topPadding: CGFloat = 16,
        horizontalPadding: CGFloat = 24,
        bottomPadding: CGFloat = 16,
        titleToContentSpacing: CGFloat = 4,
        plusAction: (() -> Void)? = nil,
        plusHelp: String = "Add",
        plusDisabled: Bool = false,
        sidebarAction: (() -> Void)? = nil,
        sidebarHelp: String = "Toggle Inspector",
        sidebarBounceValue: Bool = false,
        sidebarShortcut: KeyboardShortcut? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.topPadding = topPadding
        self.horizontalPadding = horizontalPadding
        self.bottomPadding = bottomPadding
        self.titleToContentSpacing = titleToContentSpacing
        self.plusAction = plusAction
        self.plusHelp = plusHelp
        self.plusDisabled = plusDisabled
        self.sidebarAction = sidebarAction
        self.sidebarHelp = sidebarHelp
        self.sidebarBounceValue = sidebarBounceValue
        self.sidebarShortcut = sidebarShortcut
        self.accessory = { EmptyView() }
    }
}
