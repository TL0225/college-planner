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

struct CalendarToolbarInspectorToggleView: View {
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
                    "Tasks & Deadlines",
                    systemImage: projection.sidebarPanel == .tasks ? "checkmark" : "checklist"
                )
            }

            Button {
                dispatcher.dispatch(.calendar(.sidebarPanelChange(.studyFocus)))
            } label: {
                Label(
                    "Study / Focus",
                    systemImage: projection.sidebarPanel == .studyFocus ? "checkmark" : "brain.head.profile"
                )
            }
        }
    }
}

struct AcademicsToolbarSidebarToggleView: View {
    @Binding var isInspectorPresented: Bool

    var body: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            ToolbarMetrics.glassIconLabel(systemName: "sidebar.trailing")
        }
        .toolbarIconButtonStyle()
        .help(isInspectorPresented ? "Hide stats inspector" : "Show stats inspector")
        .accessibilityLabel(isInspectorPresented ? "Hide stats inspector" : "Show stats inspector")
        .accessibilityIdentifier("toolbar.academics.sidebarToggle")
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

    private var primaryProfile: AcademicProfile? {
        let profiles = AcademicProfileReadBridge.profiles()
        return profiles.first(where: \.isPrimary) ?? profiles.first
    }

    var body: some View {
        let profile = primaryProfile
        GlassEffectContainer(spacing: 8) {
            AcademicDegreeTabBar(
                profiles: profile.map { [$0] } ?? [],
                selectedID: selectedBinding,
                showOverviewPill: false,
                centersContent: true,
                toolbarHosted: true,
                allowsAdd: false,
                allowsDelete: false,
                onAdd: {},
                onDelete: { _ in },
                onReorder: { ordered in
                    collegePersistence.reorderAcademicProfiles(ordered)
                }
            )
        }
        .frame(maxWidth: 720)
        .onAppear {
            if let profile {
                academicsScene.selectedAcademicProfileID = profile.id
            }
        }
        .onChange(of: profile?.id) { _, newID in
            guard let newID else { return }
            academicsScene.selectedAcademicProfileID = newID
        }
    }
}
