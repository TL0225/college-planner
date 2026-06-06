// GlassToolbarControls.swift
// Feature: App / Toolbar / Glass
// Purpose: Tahoe Liquid Glass toolbar primitives — consumes GlassToolbarStyle only.

import SwiftUI

// MARK: - Shared interaction driver

private struct GlassToolbarHoverPressInteractionModifier: ViewModifier {
    @Binding var isHovered: Bool
    @Binding var isPressed: Bool
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled else { return }
                        isPressed = true
                    }
                    .onEnded { _ in isPressed = false }
            )
    }
}

private extension View {
    func glassToolbarHoverPressInteraction(
        isHovered: Binding<Bool>,
        isPressed: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            GlassToolbarHoverPressInteractionModifier(
                isHovered: isHovered,
                isPressed: isPressed,
                isEnabled: isEnabled
            )
        )
    }
}

private func glassToolbarInteractionState(
    isEnabled: Bool,
    isPressed: Bool,
    isHovered: Bool,
    isFocused: Bool = false,
    isSelected: Bool = false
) -> GlassInteractionState {
    if !isEnabled { return .disabled }
    if isPressed { return .pressed }
    if isSelected { return .selected }
    if isFocused { return .focus }
    if isHovered { return .hover }
    return .idle
}

// MARK: - Surfaces

private struct GlassToolbarCapsuleSurface: ViewModifier {
    @Environment(\.glassToolbarStyle) private var style
    let interactionState: GlassInteractionState

    func body(content: Content) -> some View {
        content
            .background(style.material(for: interactionState))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary.opacity(style.theme.strokeOpacity), lineWidth: 0.5)
            }
    }
}

private struct GlassToolbarCircleSurface: ViewModifier {
    @Environment(\.glassToolbarStyle) private var style
    let interactionState: GlassInteractionState

    func body(content: Content) -> some View {
        content
            .background(style.material(for: interactionState))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(.quaternary.opacity(style.theme.strokeOpacity), lineWidth: 0.5)
            }
    }
}

extension View {
    func glassToolbarCapsule(interactionState: GlassInteractionState = .idle) -> some View {
        modifier(GlassToolbarCapsuleSurface(interactionState: interactionState))
    }

    func glassToolbarCircle(interactionState: GlassInteractionState = .idle) -> some View {
        modifier(GlassToolbarCircleSurface(interactionState: interactionState))
    }
}

// MARK: - Icon button

struct StaticToolbarGlassButton: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density

    let symbol: String
    let tip: String
    let accessibilityIdentifier: String
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var isPressed = false
    @State private var isHovered = false

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    private var interactionState: GlassInteractionState {
        glassToolbarInteractionState(
            isEnabled: isEnabled,
            isPressed: isPressed,
            isHovered: isHovered
        )
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: theme.iconPointSize, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                .frame(
                    width: theme.circleControlSize,
                    height: theme.circleControlSize
                )
        }
        .buttonStyle(.plain)
        .glassToolbarHoverPressInteraction(
            isHovered: $isHovered,
            isPressed: $isPressed,
            isEnabled: isEnabled
        )
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: theme.minHitTarget, minHeight: theme.minHitTarget)
        .disabled(!isEnabled)
        .help(tip)
        .accessibilityLabel(tip)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// MARK: - Circle toggle

struct GlassToolbarCircleButton: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density

    let symbol: String
    let tip: String
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    private var interactionState: GlassInteractionState {
        glassToolbarInteractionState(isEnabled: true, isPressed: isPressed, isHovered: isHovered)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: theme.iconPointSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: theme.circleControlSize,
                    height: theme.circleControlSize
                )
        }
        .buttonStyle(.plain)
        .glassToolbarHoverPressInteraction(isHovered: $isHovered, isPressed: $isPressed)
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: theme.minHitTarget, minHeight: theme.minHitTarget)
        .help(tip)
        .accessibilityLabel(tip)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

// MARK: - Group container

struct GlassToolbarGroup<Content: View>: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density
    @ViewBuilder var content: () -> Content

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    var body: some View {
        content()
            .padding(theme.groupInset)
            .glassToolbarCapsule()
    }
}

// MARK: - Search

struct GlassSearchFieldView: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density

    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    private var searchInteractionState: GlassInteractionState {
        glassToolbarInteractionState(
            isEnabled: true,
            isPressed: false,
            isHovered: false,
            isFocused: isFocused
        )
    }

    var body: some View {
        HStack(spacing: theme.groupSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ToolbarMetrics.controlFont)
                .focused($isFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: theme.searchFieldWidth)
        .frame(minHeight: theme.minHitTarget)
        .glassInteractiveSurface(searchInteractionState)
        .glassToolbarCapsule(interactionState: searchInteractionState)
        .accessibilityLabel(placeholder)
        .accessibilityIdentifier("toolbar.search.field")
    }
}

// MARK: - Add menu

struct GlassToolbarAddMenuButton: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density

    let onAddSemester: () -> Void
    let onAddCourse: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    private var interactionState: GlassInteractionState {
        glassToolbarInteractionState(isEnabled: true, isPressed: isPressed, isHovered: isHovered)
    }

    var body: some View {
        Menu {
            Button(String(localized: "shell.menu.add_semester"), action: onAddSemester)
            Button(String(localized: "shell.menu.add_course"), action: onAddCourse)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: theme.iconPointSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: theme.circleControlSize,
                    height: theme.circleControlSize
                )
        }
        .menuStyle(.borderlessButton)
        .glassToolbarHoverPressInteraction(isHovered: $isHovered, isPressed: $isPressed)
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: theme.minHitTarget, minHeight: theme.minHitTarget)
        .help("Add")
        .accessibilityLabel("Add")
        .accessibilityIdentifier("toolbar.add.menu")
    }
}

// MARK: - Profile avatar

struct GlassToolbarProfileAvatarButton: View {
    @Environment(\.glassToolbarStyle) private var style
    @Environment(\.toolbarDensity) private var density

    let initials: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var theme: ToolbarGlassTheme {
        style.effectiveTheme(for: density)
    }

    private var interactionState: GlassInteractionState {
        glassToolbarInteractionState(isEnabled: true, isPressed: isPressed, isHovered: isHovered)
    }

    private var avatarDiameter: CGFloat {
        theme.circleControlSize - 4
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: avatarDiameter, height: avatarDiameter)
                .overlay {
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: theme.iconPointSize - 3, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text(initials)
                            .font(.system(size: theme.iconPointSize - 4, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(theme.controlPadding)
        }
        .buttonStyle(.plain)
        .glassToolbarHoverPressInteraction(isHovered: $isHovered, isPressed: $isPressed)
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: theme.minHitTarget, minHeight: theme.minHitTarget)
        .help(String(localized: "app.toolbar.open_profile_help"))
        .accessibilityLabel(String(localized: "app.toolbar.open_profile_a11y"))
        .accessibilityIdentifier("toolbar.profile")
    }
}
