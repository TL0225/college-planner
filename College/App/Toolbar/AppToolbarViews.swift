// AppToolbarViews.swift
// Feature: App / Toolbar
// Purpose: Shared SwiftUI toolbar chrome views (no AppKit).

import CollegeAcademics
import CollegeCalendar
import SwiftUI

struct CalToolbarChromeView: View {
    let dispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState

    private var projection: CalendarSceneState.ToolbarProjection {
        calendarScene.toolbarProjection
    }

    var body: some View {
        HStack(spacing: ToolbarMetrics.itemSpacing) {
            Button {
                dispatcher.dispatch(.calendar(.previous))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "chevron.left")
            }
            .toolbarIconButtonStyle()
            .help("Previous")
            .accessibilityLabel("Previous")
            .accessibilityIdentifier("toolbar.calendar.previous")

            Text(projection.headerDate)
                .font(ToolbarMetrics.titleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                dispatcher.dispatch(.calendar(.next))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "chevron.right")
            }
            .toolbarIconButtonStyle()
            .help("Next")
            .accessibilityLabel("Next")
            .accessibilityIdentifier("toolbar.calendar.next")

            GlassEffectContainer(spacing: 3) {
                HStack(spacing: 0) {
                    ForEach(CalendarViewDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            dispatcher.dispatch(.calendar(.modeChange(mode)))
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
                        .toolbarSegmentButtonStyle()
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CalToolbarSidebarToggleView: View {
    let dispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState

    private var projection: CalendarSceneState.ToolbarProjection {
        calendarScene.toolbarProjection
    }

    var body: some View {
        Button {
            dispatcher.dispatch(.calendar(.sidebarToggle))
        } label: {
            ToolbarMetrics.glassIconLabel(systemName: "sidebar.right")
        }
        .toolbarIconButtonStyle()
        .help(
            projection.sidebarShown
                ? "Hide right sidebar (right-click to choose panel)"
                : "Show right sidebar (right-click to choose panel)"
        )
        .accessibilityLabel(
            projection.sidebarShown ? "Hide right sidebar" : "Show right sidebar"
        )
        .accessibilityIdentifier("toolbar.calendar.sidebarToggle")
        .contextMenu {
            Button {
                dispatcher.dispatch(.calendar(.sidebarPanelChange(.eventList)))
            } label: {
                Label(
                    "Event List",
                    systemImage: projection.sidebarPanel == .eventList ? "checkmark" : "list.bullet"
                )
            }

            Button {
                dispatcher.dispatch(.calendar(.sidebarPanelChange(.tasks)))
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
    let dispatcher: ToolbarDispatcher
    let academicsScene: AcademicsSceneState

    var body: some View {
        Button {
            dispatcher.dispatch(.academics(.statsSidebarToggle))
        } label: {
            ToolbarMetrics.glassIconLabel(systemName: "sidebar.left")
        }
        .toolbarIconButtonStyle()
        .help(
            academicsScene.statsSidebarShown
                ? "Hide stats sidebar"
                : "Show stats sidebar"
        )
        .accessibilityLabel(
            academicsScene.statsSidebarShown ? "Hide stats sidebar" : "Show stats sidebar"
        )
        .accessibilityIdentifier("toolbar.academics.sidebarToggle")
    }
}

struct AcademicsToolbarAddProfileButton: View {
    let collegePersistence: CollegePersistence
    let academicsScene: AcademicsSceneState

    var body: some View {
        Button {
            AcademicsToolbarProfileActions.addProfile(
                collegePersistence: collegePersistence,
                academicsScene: academicsScene
            )
        } label: {
            ToolbarMetrics.glassIconLabel(systemName: "plus")
        }
        .toolbarIconButtonStyle()
        .help(String(localized: "academic.profile.add"))
        .accessibilityLabel(String(localized: "academic.profile.add"))
    }
}

struct AcademicsDegreeScopeToolbar: View {
    let collegePersistence: CollegePersistence
    let academicsScene: AcademicsSceneState

    private var selectedBinding: Binding<UUID?> {
        Binding(
            get: { academicsScene.selectedAcademicProfileID },
            set: { academicsScene.selectedAcademicProfileID = $0 }
        )
    }

    var body: some View {
        let profiles = AcademicProfileReadBridge.profiles()
        GlassEffectContainer(spacing: 8) {
            AcademicDegreeTabBar(
                profiles: profiles,
                selectedID: selectedBinding,
                showOverviewPill: false,
                centersContent: profiles.count < 3,
                toolbarHosted: true,
                allowsAdd: false,
                allowsDelete: false,
                onAdd: {
                    AcademicsToolbarProfileActions.addProfile(
                        collegePersistence: collegePersistence,
                        academicsScene: academicsScene
                    )
                },
                onDelete: { _ in },
                onReorder: { ordered in
                    collegePersistence.reorderAcademicProfiles(ordered)
                }
            )
        }
        .frame(maxWidth: 720)
    }
}
