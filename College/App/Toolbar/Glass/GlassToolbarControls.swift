// GlassToolbarControls.swift
// Feature: App / Toolbar / Glass
// Purpose: Tahoe Liquid Glass toolbar primitives — consumes GlassToolbarStyle only.

import SwiftUI

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

    private var interactionState: GlassInteractionState {
        if !isEnabled { return .disabled }
        if isPressed { return .pressed }
        if isHovered { return .hover }
        return .idle
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: style.theme.iconPointSize, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                .frame(
                    width: style.theme.circleControlSize,
                    height: style.theme.circleControlSize
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: style.theme.minHitTarget, minHeight: style.theme.minHitTarget)
        .disabled(!isEnabled)
        .help(tip)
        .accessibilityLabel(tip)
        .accessibilityIdentifier(accessibilityIdentifier)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Circle toggle

struct GlassToolbarCircleButton: View {
    @Environment(\.glassToolbarStyle) private var style

    let symbol: String
    let tip: String
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var isHovered = false

    private var interactionState: GlassInteractionState {
        if isPressed { return .pressed }
        if isHovered { return .hover }
        return .idle
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ToolbarMetrics.iconFont)
                .foregroundStyle(.secondary)
                .frame(
                    width: style.theme.circleControlSize,
                    height: style.theme.circleControlSize
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .glassInteractiveSurface(interactionState)
        .glassToolbarCircle(interactionState: interactionState)
        .frame(minWidth: style.theme.minHitTarget, minHeight: style.theme.minHitTarget)
        .help(tip)
        .accessibilityLabel(tip)
        .accessibilityIdentifier(accessibilityIdentifier)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Group container

struct GlassToolbarGroup<Content: View>: View {
    @Environment(\.glassToolbarStyle) private var style
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(style.theme.groupInset)
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

    private var searchInteractionState: GlassInteractionState {
        isFocused ? .focus : .idle
    }

    private var fieldWidth: CGFloat {
        switch density {
        case .compact: return style.theme.searchFieldWidth * 0.85
        case .expanded: return style.theme.searchFieldWidth * 1.1
        case .regular: return style.theme.searchFieldWidth
        }
    }

    var body: some View {
        HStack(spacing: 6) {
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
        .frame(width: fieldWidth)
        .frame(minHeight: style.theme.minHitTarget)
        .glassInteractiveSurface(searchInteractionState)
        .glassToolbarCapsule(interactionState: searchInteractionState)
        .accessibilityLabel(placeholder)
        .accessibilityIdentifier("toolbar.search.field")
    }
}

// MARK: - Add menu

struct GlassToolbarAddMenuButton: View {
    @Environment(\.glassToolbarStyle) private var style

    let onAddSemester: () -> Void
    let onAddCourse: () -> Void

    var body: some View {
        Menu {
            Button(String(localized: "shell.menu.add_semester"), action: onAddSemester)
            Button(String(localized: "shell.menu.add_course"), action: onAddCourse)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: style.theme.iconPointSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: style.theme.circleControlSize,
                    height: style.theme.circleControlSize
                )
        }
        .menuStyle(.borderlessButton)
        .glassInteractiveSurface(.idle)
        .glassToolbarCircle()
        .frame(minWidth: style.theme.minHitTarget, minHeight: style.theme.minHitTarget)
        .help("Add")
        .accessibilityLabel("Add")
        .accessibilityIdentifier("toolbar.add.menu")
    }
}

// MARK: - Profile avatar

struct GlassToolbarProfileAvatarButton: View {
    @Environment(\.glassToolbarStyle) private var style

    let initials: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 28, height: 28)
                .overlay {
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text(initials)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(style.theme.controlPadding)
        }
        .buttonStyle(.plain)
        .glassInteractiveSurface(.idle)
        .glassToolbarCircle()
        .frame(minWidth: style.theme.minHitTarget, minHeight: style.theme.minHitTarget)
        .help(String(localized: "app.toolbar.open_profile_help"))
        .accessibilityLabel(String(localized: "app.toolbar.open_profile_a11y"))
        .accessibilityIdentifier("toolbar.profile")
    }
}
