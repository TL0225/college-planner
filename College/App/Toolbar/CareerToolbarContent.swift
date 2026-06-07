// CareerToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI
import CollegeCareer

struct CareerToolbarContent: ToolbarContent {
    let activePage: AppPage
    @FocusedValue(\.activePage) private var focusedActivePage
    @Environment(AppContainer.self) private var appContainer

    private var careerScene: CareerSceneState { appContainer.careerScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    private var careerPageIsActive: Bool {
        (focusedActivePage ?? activePage) == .career
    }

    private var subviewBinding: Binding<CareerSubView> {
        Binding(
            get: { careerScene.selectedView },
            set: { careerScene.select($0) }
        )
    }

    var body: some ToolbarContent {
        ToolbarItem(id: "career.subviews", placement: .principal) {
            GlassEffectContainer(spacing: 8) {
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
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            if careerScene.selectedView == .board {
                CareerBoardLayoutMenu(
                    layout: careerScene.boardLayout,
                    onSelect: { careerScene.setBoardLayout($0) }
                )
                .buttonStyle(.plain)

                Button {
                    toolbarDispatcher.dispatch(.career(.copyBoardMarkdown))
                } label: {
                    ToolbarMetrics.glassIconLabel(systemName: "doc.on.doc")
                }
                .toolbarIconButtonStyle()
                .help("Copy board as Markdown table")
                .accessibilityLabel("Copy board as Markdown table")
                .accessibilityIdentifier("toolbar.career.copyMarkdown")
            }
            Button {
                toolbarDispatcher.dispatch(.career(.addApplication))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "plus")
            }
            .toolbarIconButtonStyle()
            .help("Add application")
            .accessibilityLabel("Add application")
            .accessibilityIdentifier("toolbar.career.add")
            .disabled(!careerPageIsActive)
            .keyboardShortcut("n", modifiers: [.command])
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
