// MainWindowToolbar.swift
// Feature: App
// Purpose: App module — MainWindowToolbar.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

/// Window toolbar for the main NavigationSplitView detail column (macOS Liquid Glass).
///
/// Page titles use `navigationTitle` on the detail column (`ContentView.mainNavigationSplitTitle`).
struct MainWindowToolbar: ToolbarContent {
    let activePage: AppPage
    @Binding var academicsInspectorPresented: Bool

    /// Web shortcut tabs only — Brightspace uses the window title with no toolbar chrome.
    private var showsWebPortalControls: Bool {
        if case .webShortcut = activePage { return true }
        return false
    }

    var body: some ToolbarContent {
        DefaultToolbarItem(kind: .sidebarToggle, placement: .automatic)

        if showsWebPortalControls {
            ToolbarItem(id: "portal.home", placement: .navigation) {
                PortalHomeToolbarButton()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                WebNavigationToolbar()
            }
        }

        if activePage == .career {
            CareerWindowToolbarItems(activePage: activePage)
        }
        if activePage == .calendar {
            CalendarWindowToolbarItems()
        }
        if activePage == .academics {
            AcademicsWindowToolbarItems(academicsInspectorPresented: $academicsInspectorPresented)
        }
    }
}

// MARK: - Per-page toolbar fragments

private struct AcademicsWindowToolbarItems: ToolbarContent {
    @Binding var academicsInspectorPresented: Bool
    @Environment(AppToolbarCoordinator.self) private var toolbarCoordinator

    var body: some ToolbarContent {
        ToolbarItem(id: "academics.degreeScope", placement: .principal) {
            AcademicsDegreeScopeToolbar()
        }
        ToolbarItem(id: "academics.sidebarToggle", placement: .primaryAction) {
            AcademicsToolbarSidebarToggleView(coordinator: toolbarCoordinator)
        }
    }
}

private struct CalendarWindowToolbarItems: ToolbarContent {
    @Environment(AppToolbarCoordinator.self) private var toolbarCoordinator

    var body: some ToolbarContent {
        ToolbarItem(id: "cal.chrome", placement: .principal) {
            CalToolbarChromeView(coordinator: toolbarCoordinator)
        }
        ToolbarItem(id: "cal.sidebarToggle", placement: .primaryAction) {
            CalToolbarSidebarToggleView(coordinator: toolbarCoordinator)
        }
    }
}

private struct CareerWindowToolbarItems: ToolbarContent {
    let activePage: AppPage
    @FocusedValue(\.activePage) private var focusedActivePage
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(CareerToolbarState.self) private var careerToolbar

    private var careerPageIsActive: Bool {
        (focusedActivePage ?? activePage) == .career
    }

    private var subviewBinding: Binding<CareerSubView> {
        Binding(
            get: { careerToolbar.selectedView },
            set: { careerToolbar.select($0) }
        )
    }

    var body: some ToolbarContent {
        ToolbarItem(id: "career.subviews", placement: .principal) {
            Picker("Career Views", selection: subviewBinding) {
                Text("Board").tag(CareerSubView.board)
                Text("Openings").tag(CareerSubView.openings)
                Text("Stats").tag(CareerSubView.stats)
                Text("Resumes").tag(CareerSubView.resumes)
                Text("Stories").tag(CareerSubView.stories)
                Text("Networking").tag(CareerSubView.networking)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if careerToolbar.selectedView == .board {
                CareerBoardLayoutMenu(
                    layout: careerToolbar.boardLayout,
                    onSelect: { careerToolbar.setBoardLayout($0) }
                )
                Button {
                    copyBoardMarkdown()
                } label: {
                    Label("Copy board", systemImage: "doc.on.doc")
                }
                .help("Copy board as Markdown table")
            }
            Button {
                NotificationCenter.default.post(name: .careerOpenAddApplication, object: nil)
            } label: {
                Label("Add application", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!careerPageIsActive)
            .help("Add application")
        }
    }

    private func copyBoardMarkdown() {
        let apps = (try? collegePersistence.careerRepository.fetchApplications(limit: 500)) ?? []
        let md = CareerBoardMarkdownExport.table(from: apps)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }
}

/// Portal-home control for embedded web tabs (title comes from `navigationTitle`).
struct WebNavigationToolbar: View {
    @Environment(WebPortalToolbarState.self) private var toolbar

    var body: some View {
        HStack(spacing: 8) {
            Button { toolbar.back() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!toolbar.canGoBack)
            .help("Back")

            Button { toolbar.forward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!toolbar.canGoForward)
            .help("Forward")

            Button { toolbar.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
        }
    }
}

struct PortalHomeToolbarButton: View {
    @Environment(WebPortalToolbarState.self) private var toolbar

    var body: some View {
        Button { toolbar.portalHome() } label: {
            Label(
                String(localized: "brightspace.toolbar.portal_home_a11y"),
                systemImage: "house"
            )
            .font(ToolbarMetrics.iconFont)
            .labelStyle(.iconOnly)
        }
        .help(String(localized: "brightspace.toolbar.portal_home_help"))
        .accessibilityLabel(String(localized: "brightspace.toolbar.portal_home_a11y"))
    }
}

