// AppToolbarViews.swift
// Feature: App / Toolbar
// Purpose: Shared SwiftUI toolbar chrome views (no AppKit).

import SwiftUI

struct CalToolbarChromeView: View {
    @Environment(AppContainer.self) private var appContainer

    private var calendarScene: CalendarSceneState { appContainer.calendarScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    private var projection: CalendarSceneState.ToolbarProjection {
        calendarScene.toolbarProjection
    }

    var body: some View {
        HStack(spacing: 12) {
            GlassToolbarCircleButton(
                symbol: "chevron.left",
                tip: "Previous",
                accessibilityIdentifier: "toolbar.calendar.previous"
            ) {
                toolbarDispatcher.dispatch(.calendar(.previous))
            }

            Text(projection.headerDate)
                .font(ToolbarMetrics.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)

            GlassToolbarCircleButton(
                symbol: "chevron.right",
                tip: "Next",
                accessibilityIdentifier: "toolbar.calendar.next"
            ) {
                toolbarDispatcher.dispatch(.calendar(.next))
            }

            GlassToolbarGroup {
                HStack(spacing: 0) {
                    ForEach(CalendarViewDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            toolbarDispatcher.dispatch(.calendar(.modeChange(mode)))
                        } label: {
                            Text(mode.rawValue)
                                .font(ToolbarMetrics.font(projection.viewMode == mode ? .semibold : .regular))
                                .foregroundStyle(
                                    projection.viewMode == mode
                                        ? AnyShapeStyle(.primary)
                                        : AnyShapeStyle(.secondary)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    projection.viewMode == mode
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                                        : AnyShapeStyle(Color.clear)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CalToolbarSidebarToggleView: View {
    @Environment(AppContainer.self) private var appContainer

    private var calendarScene: CalendarSceneState { appContainer.calendarScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    private var projection: CalendarSceneState.ToolbarProjection {
        calendarScene.toolbarProjection
    }

    var body: some View {
        GlassToolbarCircleButton(
            symbol: "sidebar.right",
            tip: projection.sidebarShown
                ? "Hide right sidebar (right-click to choose panel)"
                : "Show right sidebar (right-click to choose panel)",
            accessibilityIdentifier: "toolbar.calendar.sidebarToggle"
        ) {
            toolbarDispatcher.dispatch(.calendar(.sidebarToggle))
        }
        .contextMenu {
            Button {
                toolbarDispatcher.dispatch(.calendar(.sidebarPanelChange(.eventList)))
            } label: {
                Label(
                    "Event List",
                    systemImage: projection.sidebarPanel == .eventList ? "checkmark" : "list.bullet"
                )
            }

            Button {
                toolbarDispatcher.dispatch(.calendar(.sidebarPanelChange(.tasks)))
            } label: {
                Label(
                    "Task List",
                    systemImage: projection.sidebarPanel == .tasks ? "checkmark" : "checklist"
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct AcademicsToolbarSidebarToggleView: View {
    @Environment(AppContainer.self) private var appContainer

    private var academicsScene: AcademicsSceneState { appContainer.academicsScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    var body: some View {
        GlassToolbarCircleButton(
            symbol: "sidebar.left",
            tip: academicsScene.statsSidebarShown
                ? "Hide stats sidebar"
                : "Show stats sidebar",
            accessibilityIdentifier: "toolbar.academics.sidebarToggle"
        ) {
            toolbarDispatcher.dispatch(.academics(.statsSidebarToggle))
        }
    }
}

struct SafeSidebarToggleView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var lastToggleTime = Date.distantPast

    var body: some View {
        GlassToolbarCircleButton(
            symbol: "sidebar.left",
            tip: "Toggle Sidebar",
            accessibilityIdentifier: "toolbar.shell.sidebarToggle"
        ) {
            let now = Date()
            guard now.timeIntervalSince(lastToggleTime) > 0.4 else { return }
            lastToggleTime = now
            withAnimation(.easeInOut(duration: 0.2)) {
                switch columnVisibility {
                case .all, .doubleColumn, .automatic:
                    columnVisibility = .detailOnly
                default:
                    columnVisibility = .all
                }
            }
        }
    }
}
