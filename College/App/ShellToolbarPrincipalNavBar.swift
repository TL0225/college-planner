// ShellToolbarPrincipalNavBar.swift
// Feature: App
// Purpose: App module — ShellToolbarPrincipalNavBar.
// Data: CollegePersistence / repositories when applicable.

//
//  ShellToolbarPrincipalNavBar.swift
//  College
//
//  Shared principal toolbar strip for Overview + Documents. Hosted from `ContentView.shellToolbar`
//  (not inside `NavigationSplitView` detail) so unified-toolbar layout stays stable when switching.
//

import SwiftUI


private enum ShellToolbarPrincipalNavMotion {
    static let hoverDuration: Double = 0.18
}

enum ShellToolbarPrincipalNavLayout {
    static let principalWidth: CGFloat = 460
    static let principalHeight: CGFloat = 30
}

/// Overview / Academics / Documents quick switches in the window toolbar (`.principal`).
struct ShellToolbarPrincipalNavBar: View {
    @Binding var activePage: AppPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @State private var hoveredToolbarPage: AppPage?

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    var body: some View {
        let isCalendarActive = activePage == .calendar

        HStack(spacing: 4) {
            navButton(
                title: String(localized: "app.page.overview"),
                systemImage: "square.grid.2x2",
                page: .degree
            )
            navButton(
                title: String(localized: "app.page.academics"),
                systemImage: "graduationcap",
                page: .academics
            )
            navButton(
                title: String(localized: "app.page.calendar"),
                systemImage: "calendar",
                page: .calendar
            )
            navButton(
                title: String(localized: "app.page.documents"),
                systemImage: "folder",
                page: .documents
            )
        }
        .frame(width: ShellToolbarPrincipalNavLayout.principalWidth, height: ShellToolbarPrincipalNavLayout.principalHeight, alignment: .center)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .offset(x: isCalendarActive ? -36 : 0)
    }

    @ViewBuilder
    private func navButton(title: String, systemImage: String, page: AppPage) -> some View {
        let isActive = activePage == page
        let isHovered = hoveredToolbarPage == page

        Button {
            // Keep page changes immediate to avoid one-frame principal-toolbar recentering jitter.
            activePage = page
        } label: {
            Label(title, systemImage: systemImage)
                .font(ToolbarMetrics.controlFont)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.13) : (isHovered ? Color.primary.opacity(0.06) : .clear))
                }
                .overlay {
                    Capsule()
                        .stroke(isActive ? Color.accentColor.opacity(0.35) : .primary.opacity(isHovered ? 0.3 : 0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .animation(motionReduced ? nil : .easeOut(duration: ShellToolbarPrincipalNavMotion.hoverDuration), value: hoveredToolbarPage)
        .animation(motionReduced ? nil : .easeOut(duration: 0.15), value: activePage)
        .onHover { hovering in
            hoveredToolbarPage = hovering ? page : nil
        }
    }
}

